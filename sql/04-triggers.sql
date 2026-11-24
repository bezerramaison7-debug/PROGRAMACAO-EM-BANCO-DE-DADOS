USE LojaVirtual;
GO
CREATE TABLE dbo.AuditoriaPrecos (
    AuditoriaID int IDENTITY PRIMARY KEY,
    ProdutoID int NOT NULL,
    PrecoAnterior decimal(10,2) NOT NULL,
    PrecoNovo decimal(10,2) NOT NULL,
    DataAlteracao datetime2 NOT NULL DEFAULT SYSDATETIME(),
    Responsavel sysname NOT NULL DEFAULT ORIGINAL_LOGIN()
);
GO
CREATE OR ALTER TRIGGER dbo.trg_AuditarPrecoProduto ON dbo.Produtos AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.AuditoriaPrecos (ProdutoID,PrecoAnterior,PrecoNovo)
    SELECT i.ProdutoID,d.Preco,i.Preco
    FROM inserted i JOIN deleted d ON d.ProdutoID=i.ProdutoID WHERE i.Preco<>d.Preco;
END;
GO
CREATE OR ALTER TRIGGER dbo.trg_ValidarEstoquePedido ON dbo.Pedidos AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(StatusPedido) RETURN;
    DECLARE @Demanda TABLE (ProdutoID int PRIMARY KEY,Quantidade bigint NOT NULL);
    INSERT @Demanda (ProdutoID,Quantidade)
    SELECT ip.ProdutoID,SUM(CONVERT(bigint,ip.Quantidade))
    FROM inserted i JOIN deleted d ON d.PedidoID=i.PedidoID
    JOIN dbo.ItensPedido ip ON ip.PedidoID=i.PedidoID
    WHERE i.StatusPedido='Pago' AND d.StatusPedido<>'Pago'
    GROUP BY ip.ProdutoID;

    IF EXISTS (
        SELECT 1 FROM @Demanda d JOIN dbo.Produtos p WITH (UPDLOCK,HOLDLOCK)
        ON p.ProdutoID=d.ProdutoID WHERE p.Estoque<d.Quantidade
    ) THROW 50021,N'Não há estoque suficiente para confirmar o pedido.',1;

    UPDATE p SET Estoque=p.Estoque-d.Quantidade
    FROM dbo.Produtos p JOIN @Demanda d ON d.ProdutoID=p.ProdutoID;
END;
GO
SET NOCOUNT ON;
UPDATE dbo.Produtos SET Estoque=Estoque+1 WHERE ProdutoID=1;
IF EXISTS (SELECT 1 FROM dbo.AuditoriaPrecos) THROW 51020,N'Estoque gerou auditoria de preço.',1;
SELECT COUNT(*) AS AuditoriasAposEstoque FROM dbo.AuditoriaPrecos;
UPDATE dbo.Produtos SET Preco=130 WHERE ProdutoID=1;
UPDATE dbo.Produtos SET Preco=Preco+5 WHERE ProdutoID IN (2,3);
IF (SELECT COUNT(*) FROM dbo.AuditoriaPrecos)<>3 THROW 51021,N'Auditoria incompleta.',1;
SELECT ProdutoID,PrecoAnterior,PrecoNovo,CONVERT(date,DataAlteracao) AS DataAlteracao,
       CASE WHEN Responsavel=ORIGINAL_LOGIN() THEN N'Conta de laboratório' ELSE N'Outra conta' END AS Responsavel
FROM dbo.AuditoriaPrecos ORDER BY AuditoriaID;

INSERT dbo.Pedidos (ClienteID,DataPedido,StatusPedido,ValorTotal) VALUES
    (1,'20260401','Pendente',130),(2,'20260402','Pendente',8500),
    (1,'20260403','Pendente',85),(2,'20260404','Pendente',170);
INSERT dbo.ItensPedido (PedidoID,ProdutoID,Quantidade,PrecoUnitario) VALUES
    (4,1,1,130),(5,2,100,85),(6,2,1,85),(7,2,2,85);
DECLARE @Teclado int=(SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=1),
        @Mouse int=(SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=2);
SELECT @Teclado AS TecladoAntes,@Mouse AS MouseAntes;
UPDATE dbo.Pedidos SET StatusPedido='Pago' WHERE PedidoID=4;
IF (SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=1)<>@Teclado-1
    THROW 51022,N'Baixa do pedido válido divergente.',1;
UPDATE dbo.Pedidos SET StatusPedido='Pago' WHERE PedidoID=4;
IF (SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=1)<>@Teclado-1
    THROW 51023,N'Pedido já pago baixou estoque novamente.',1;
SELECT Estoque AS TecladoAposPagamentoERepeticao FROM dbo.Produtos WHERE ProdutoID=1;
UPDATE dbo.Pedidos SET StatusPedido='Pago' WHERE PedidoID IN (6,7);
IF (SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=2)<>@Mouse-3
    THROW 51024,N'Baixa agregada divergente.',1;
SELECT Estoque AS MouseAposLote FROM dbo.Produtos WHERE ProdutoID=2;
BEGIN TRY
    UPDATE dbo.Pedidos SET StatusPedido='Pago' WHERE PedidoID=5;
    THROW 51025,N'Pedido sem estoque foi aceito.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>50021 THROW;
    SELECT ERROR_NUMBER() AS ErroEstoque,ERROR_MESSAGE() AS Mensagem;
END CATCH;
IF (SELECT StatusPedido FROM dbo.Pedidos WHERE PedidoID=5)<>'Pendente'
OR (SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=2)<>@Mouse-3
    THROW 51026,N'Estoque ou status alterado após rejeição.',1;
SELECT PedidoID,StatusPedido FROM dbo.Pedidos WHERE PedidoID BETWEEN 4 AND 7 ORDER BY PedidoID;
DISABLE TRIGGER dbo.trg_ValidarEstoquePedido ON dbo.Pedidos;
SELECT is_disabled AS DesabilitadaDuranteTeste FROM sys.triggers WHERE name='trg_ValidarEstoquePedido';
ENABLE TRIGGER dbo.trg_ValidarEstoquePedido ON dbo.Pedidos;
SELECT name,is_disabled FROM sys.triggers
WHERE name IN ('trg_ValidarEstoquePedido','trg_AuditarPrecoProduto') ORDER BY name;
