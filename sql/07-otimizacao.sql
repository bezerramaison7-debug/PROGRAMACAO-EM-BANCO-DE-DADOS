USE LojaVirtual;
GO
SET NOCOUNT ON;
-- Volume sintético exclusivo para medir seletividade. Datas entre 2023 e 2027.
WITH Numeros AS (
    SELECT TOP (20000) ROW_NUMBER() OVER (ORDER BY a.object_id,b.object_id) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT dbo.Pedidos (ClienteID,DataPedido,StatusPedido,ValorTotal)
SELECT CASE WHEN n%40=0 THEN 1 WHEN n%2=0 THEN 2 ELSE 3 END,
       DATEADD(day,CONVERT(int,n%1826),CONVERT(date,'20230101')),
       'Cancelado',0
FROM Numeros;

EXEC sys.sp_helpindex 'dbo.Pedidos';
SELECT name,type_desc,is_unique,is_disabled FROM sys.indexes
WHERE object_id=OBJECT_ID(N'dbo.Pedidos') ORDER BY index_id;
GO
-- PLANO: inicial
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SET STATISTICS XML ON;
SELECT PedidoID,ClienteID,DataPedido,StatusPedido,ValorTotal FROM dbo.Pedidos
WHERE ClienteID=1 AND DataPedido>='20260101' AND DataPedido<'20260401';
SET STATISTICS XML OFF;
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
-- PLANO: nao-sargavel
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SET STATISTICS XML ON;
SELECT PedidoID,ClienteID,DataPedido,ValorTotal FROM dbo.Pedidos WHERE YEAR(DataPedido)=2026;
SET STATISTICS XML OFF;
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
-- PLANO: sargavel
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SET STATISTICS XML ON;
SELECT PedidoID,ClienteID,DataPedido,ValorTotal FROM dbo.Pedidos
WHERE DataPedido>='20260101' AND DataPedido<'20270101';
SET STATISTICS XML OFF;
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
IF EXISTS (
    SELECT PedidoID FROM dbo.Pedidos WHERE YEAR(DataPedido)=2026
    EXCEPT SELECT PedidoID FROM dbo.Pedidos WHERE DataPedido>='20260101' AND DataPedido<'20270101'
) OR EXISTS (
    SELECT PedidoID FROM dbo.Pedidos WHERE DataPedido>='20260101' AND DataPedido<'20270101'
    EXCEPT SELECT PedidoID FROM dbo.Pedidos WHERE YEAR(DataPedido)=2026
) THROW 51050,N'Os predicados retornaram pedidos diferentes.',1;
SELECT COUNT(*) AS PedidosEquivalentes FROM dbo.Pedidos WHERE YEAR(DataPedido)=2026;
CREATE NONCLUSTERED INDEX IX_Pedidos_Cliente_Data ON dbo.Pedidos (ClienteID,DataPedido)
INCLUDE (StatusPedido,ValorTotal);
GO
-- PLANO: apos-indice
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SET STATISTICS XML ON;
SELECT PedidoID,ClienteID,DataPedido,StatusPedido,ValorTotal FROM dbo.Pedidos
WHERE ClienteID=1 AND DataPedido>='20260101' AND DataPedido<'20260401';
SET STATISTICS XML OFF;
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
-- PLANO: somente-cliente
SET STATISTICS XML ON;
SELECT PedidoID,ClienteID,DataPedido,StatusPedido,ValorTotal FROM dbo.Pedidos WHERE ClienteID=1;
SET STATISTICS XML OFF;
GO
-- PLANO: somente-data
SET STATISTICS XML ON;
SELECT PedidoID,ClienteID,DataPedido,StatusPedido,ValorTotal FROM dbo.Pedidos
WHERE DataPedido>='20260101' AND DataPedido<'20260401';
SET STATISTICS XML OFF;
GO
SELECT ClienteID,COUNT(*) AS QuantidadePedidos FROM dbo.Pedidos GROUP BY ClienteID ORDER BY QuantidadePedidos DESC;
DBCC SHOW_STATISTICS ('dbo.Pedidos','IX_Pedidos_Cliente_Data');
EXEC sys.sp_helpindex 'dbo.ItensPedido';
GO
-- PLANO: juncao
SET STATISTICS XML ON;
SELECT p.ProdutoID,p.Nome,SUM(i.Quantidade) AS QuantidadeNosItens
FROM dbo.Produtos p JOIN dbo.ItensPedido i ON i.ProdutoID=p.ProdutoID
GROUP BY p.ProdutoID,p.Nome ORDER BY QuantidadeNosItens DESC,p.ProdutoID;
SET STATISTICS XML OFF;
-- Proposta (somente análise): ItensPedido (ProdutoID) INCLUDE (Quantidade).
