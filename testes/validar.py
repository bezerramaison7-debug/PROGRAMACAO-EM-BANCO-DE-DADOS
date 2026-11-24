"""Executa os oito checkpoints contra uma instância isolada de SQL Server."""
import hashlib
import json
import os
import re
import time
import xml.etree.ElementTree as ET
from decimal import Decimal
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from statistics import median

import pymssql


ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get('EVIDENCIAS', ROOT / 'evidencias'))
DB = 'LojaVirtual'


def abrir(database=DB):
    return pymssql.connect(
        server=os.environ.get('SQL_HOST', '127.0.0.1'),
        port=os.environ.get('SQL_PORT', '1433'),
        user=os.environ.get('SQL_USER', 'sa'),
        password=os.environ['SQLCMDPASSWORD'],
        database=database, autocommit=True, charset='UTF-8',
        login_timeout=8, timeout=20,
    )


def consultar(conn, query):
    with conn.cursor() as cursor:
        cursor.execute(query)
        return cursor.fetchall()


def valor(conn, query):
    return consultar(conn, query)[0][0]


def executar_arquivo(conn, arquivo, log, planos):
    for batch in re.split(r'^\s*GO\s*$', arquivo.read_text(), flags=re.M | re.I):
        if not batch.strip():
            continue
        msgs = []

        def mensagem(_estado, _gravidade, _nome, _proc, _linha, texto):
            msgs.append(texto.decode('utf-8', 'replace').strip() if isinstance(texto, bytes) else str(texto))

        conn._conn.set_msghandler(mensagem)
        nome = re.search(r'^-- PLANO: ([\w-]+)', batch, re.M)
        contador = 0
        plano = None
        with conn.cursor() as cursor:
            cursor.execute(batch)
            while True:
                if cursor.description:
                    colunas = [c[0] for c in cursor.description]
                    linhas = cursor.fetchall()
                    if linhas and isinstance(linhas[0][0], str) and '<ShowPlanXML' in linhas[0][0][:300]:
                        plano = linhas[0][0]
                    else:
                        contador = len(linhas)
                        log.write(' | '.join(colunas) + '\n')
                        for linha in linhas[:16]:
                            log.write(' | '.join('NULL' if x is None else str(x) for x in linha) + '\n')
                        if contador > 16 or nome:
                            log.write(f'Linhas retornadas: {contador}\n')
                        log.write('\n')
                if not cursor.nextset():
                    break
        for msg in msgs:
            if msg:
                log.write(msg + '\n')
        if nome:
            assert plano, f'Plano real ausente em {nome[1]}'
            raiz = ET.fromstring(plano)
            ns = {'p': raiz.tag.split('}')[0][1:]}
            ops = [x.attrib['PhysicalOp'] for x in raiz.findall('.//p:RelOp', ns)]
            assert raiz.find('.//p:RunTimeCountersPerThread', ns) is not None
            leituras = sum(int(x) for x in re.findall(r'(?<![\w-])logical reads (\d+)', ' '.join(msgs)))
            tempo = raiz.find('.//p:QueryTimeStats', ns)
            chave = nome[1]
            (OUT / f'r07-{chave}.sqlplan').write_text(plano, encoding='utf-8')
            dados = {'operadores': ops, 'linhas': contador}
            if 'SET STATISTICS IO ON' in batch:
                assert tempo is not None and any('logical reads ' in msg for msg in msgs), chave
                dados.update(leituras=leituras, cpu_ms=int(tempo.attrib['CpuTime']),
                             decorrido_ms=int(tempo.attrib['ElapsedTime']))
            planos[chave] = dados
            log.write(f'Plano real {chave}: {dados}\n')


def concorrencia(log):
    with abrir() as a, abrir() as b, abrir() as monitor, ThreadPoolExecutor(max_workers=1) as pool:
        id_a, id_b = valor(a, 'SELECT @@SPID'), valor(b, 'SELECT @@SPID')

        def aguardar_bloqueio():
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                info = consultar(monitor, f'''
                    SELECT wait_type,wait_time,blocking_session_id
                    FROM sys.dm_exec_requests WHERE session_id={id_b} AND blocking_session_id={id_a}
                ''')
                if info:
                    return info[0]
                time.sleep(0.03)
            raise AssertionError('A sessão B não foi observada bloqueada pela sessão A.')

        def disputa(rotulo, comando_a, comando_b, finalizar):
            inicio = time.monotonic()
            with a.cursor() as cursor:
                cursor.execute('BEGIN TRANSACTION; ' + comando_a)
            try:
                futuro = pool.submit(consultar, b, comando_b)
                espera, ms, bloqueador = aguardar_bloqueio()
                assert bloqueador == id_a
                log.write(f'{rotulo} | Sessão A bloqueia sessão B | {espera} | espera DMV: {ms} ms\n')
            finally:
                with a.cursor() as cursor:
                    cursor.execute(finalizar + ' TRANSACTION;')
            retorno = futuro.result(timeout=10)
            assert valor(a, 'SELECT @@TRANCOUNT') == valor(b, 'SELECT @@TRANCOUNT') == 0
            log.write(f'{rotulo} | Sessão A: {finalizar} | Sessão B: {retorno} | teste: '
                      f'{(time.monotonic()-inicio)*1000:.0f} ms | @@TRANCOUNT A/B: 0/0\n')
            return retorno

        inicial = valor(a, 'SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=1')
        mudanca = 'UPDATE dbo.Produtos SET Estoque=Estoque+1 WHERE ProdutoID=1;'
        leitura = 'SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=1;'
        resultado = disputa('Estoque', mudanca, mudanca + leitura, 'ROLLBACK')
        assert resultado == [(inicial+1,)]
        with a.cursor() as cursor:
            cursor.execute('UPDATE dbo.Produtos SET Estoque=Estoque-1 WHERE ProdutoID=1;')
        comando = "EXEC dbo.sp_ProcessarPagamento 8,'Pix';"
        defesa = 'BEGIN TRY ' + comando + ' SELECT 0; END TRY BEGIN CATCH SELECT ERROR_NUMBER(); END CATCH;'
        assert disputa('Pagamento 8', comando, defesa, 'COMMIT') == [(50011,)]
        assert valor(a, 'SELECT COUNT(*) FROM dbo.Pagamentos WHERE PedidoID=8') == 1
        assert valor(a, leitura) == inicial-1
        log.write(f'Pedido 8 | Pagamentos: 1 | estoque inicial: {inicial} | estoque final: {inicial-1}\n')
        for nivel in ('READ COMMITTED', 'SERIALIZABLE'):
            resposta = disputa(nivel, mudanca, f'SET TRANSACTION ISOLATION LEVEL {nivel}; ' + leitura, 'ROLLBACK')
            assert resposta == [(inicial-1,)]


def medir_alertas(conn, log):
    repeticoes = 30
    comandos = {
        'Cursor': 'EXEC dbo.sp_GerarAlertasCursor;',
        'Conjunto': """
            INSERT dbo.AlertasEstoque (ProdutoID,NivelAlerta,Mensagem)
            SELECT ProdutoID, CASE WHEN Estoque=0 THEN 'URGENTE' ELSE 'ATENCAO' END,
                   CONCAT(N'Produto ',Nome,N': estoque atual = ',Estoque,N'.')
            FROM dbo.Produtos WHERE Estoque<=5;
        """,
    }
    valores = {nome: [] for nome in comandos}
    antes = valor(conn, 'SELECT COUNT(*) FROM dbo.AlertasEstoque')
    for _ in range(repeticoes):
        for nome, comando in comandos.items():
            with conn.cursor() as cursor:
                cursor.execute('BEGIN TRANSACTION;')
                try:
                    inicio = time.perf_counter_ns()
                    cursor.execute(comando)
                    while cursor.nextset():
                        pass
                    valores[nome].append((time.perf_counter_ns() - inicio) / 1000)
                    cursor.execute('SELECT COUNT(*) FROM dbo.AlertasEstoque;')
                    assert cursor.fetchone()[0] == antes * 2
                finally:
                    cursor.execute('ROLLBACK TRANSACTION;')
    assert valor(conn, 'SELECT COUNT(*) FROM dbo.AlertasEstoque') == antes
    for nome, duracoes in valores.items():
        log.write(f'Mediana cliente-servidor | {nome} | {repeticoes} repetições | {median(duracoes):.1f} us\n')


def monitorar(log):
    with abrir() as observada, abrir() as observadora, ThreadPoolExecutor(max_workers=1) as pool:
        sessao = valor(observada, 'SELECT @@SPID')
        futuro = pool.submit(consultar, observada, """
            WAITFOR DELAY '00:00:02';
            SELECT COUNT(*) FROM dbo.vw_CatalogoPublico;
        """)
        deadline = time.monotonic() + 1.5
        dados = []
        while time.monotonic() < deadline and not dados:
            dados = consultar(observadora, f"""
                SELECT status,command,cpu_time,total_elapsed_time,wait_type
                FROM sys.dm_exec_requests WHERE session_id={sessao} AND database_id=DB_ID()
            """)
            time.sleep(0.04)
        assert dados, 'Requisição de laboratório não observada.'
        retorno = futuro.result(timeout=6)
        log.write('Sessão observada | status | comando | CPU ms | decorrido ms | espera\n')
        for linha in dados:
            log.write('Catálogo A | ' + ' | '.join(str(x) for x in linha) + '\n')
        log.write(f'Linhas públicas após a espera controlada: {retorno[0][0]}\n')
        assert retorno == [(5,)]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    planos = {}
    check = []
    with abrir('master') as conn:
        versao = consultar(conn, "SELECT CONVERT(varchar(30),SERVERPROPERTY('ProductVersion')), "
                               "CONVERT(varchar(80),SERVERPROPERTY('Edition'))")[0]
        for numero, sql in enumerate(sorted((ROOT / 'sql').glob('*.sql')), 1):
            with (OUT / f'r{numero:02}.txt').open('w', encoding='utf-8') as log:
                log.write(f'Roteiro {numero} | SQL Server {versao[0]} | {versao[1]}\n\n')
                executar_arquivo(conn, sql, log, planos)
                if numero == 2:
                    assert consultar(conn, '''
                        SELECT c.ClienteID,COUNT(p.PedidoID),COALESCE(SUM(p.ValorTotal),0)
                        FROM dbo.Clientes c LEFT JOIN dbo.Pedidos p ON c.ClienteID=p.ClienteID
                        GROUP BY c.ClienteID ORDER BY c.ClienteID
                    ''') == [(1, 2, Decimal('320')), (2, 1, Decimal('85')), (3, 0, Decimal('0'))]
                    assert consultar(conn, 'SELECT ProdutoID FROM dbo.Produtos WHERE Estoque<10 ORDER BY ProdutoID') == [
                        (2,), (3,), (4,)
                    ]
                    log.write('Síntese: totais, cliente sem pedidos e reposição conferidos.\n')
                if numero == 3:
                    assert valor(conn, 'SELECT Preco FROM dbo.vw_ProdutosAtivos WHERE ProdutoID=1') == Decimal('125')
                    assert valor(conn, 'SELECT COUNT(*) FROM dbo.fn_PedidosPorCliente(1)') == 2
                    assert valor(conn, 'SELECT dbo.fn_CalcularSubtotal(3,12.90)') == Decimal('38.70')
                    assert consultar(conn, '''
                        SELECT PedidoID,ValorCalculado FROM dbo.vw_ResumoPedidos
                        EXCEPT
                        SELECT PedidoID,SUM(dbo.fn_CalcularSubtotal(Quantidade,PrecoUnitario))
                        FROM dbo.ItensPedido GROUP BY PedidoID
                    ''') == []
                    log.write('Integração: preço, função e totais da view conferidos.\n')
                if numero == 5:
                    concorrencia(log)
                if numero == 6:
                    medir_alertas(conn, log)
                if numero == 7:
                    assert planos['inicial']['linhas'] == planos['apos-indice']['linhas']
                    assert planos['nao-sargavel']['linhas'] == planos['sargavel']['linhas']
                if numero == 8:
                    monitorar(log)
                assert valor(conn, 'SELECT @@TRANCOUNT') == 0
                log.write(f'\nCheckpoint R{numero} validado. Transações na sessão principal: 0.\n')
            digest = hashlib.sha256(sql.read_bytes()).hexdigest()
            check.append(f'R{numero} PASSOU | {sql.name} | SHA-256 {digest}')
            print(check[-1], flush=True)
    (OUT / 'r07-metricas.json').write_text(json.dumps(planos, indent=2, ensure_ascii=False)+'\n')
    (OUT / 'validacao.txt').write_text(f'SQL Server {versao[0]} | {versao[1]}\n'+'\n'.join(check)+'\n')


if __name__ == '__main__':
    main()
