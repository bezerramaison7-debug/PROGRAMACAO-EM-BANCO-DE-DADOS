USE LojaVirtual;
GO
CREATE OR ALTER VIEW dbo.vw_ProdutosAtivos AS
SELECT p.ProdutoID,p.Nome,c.Nome AS Categoria,p.Preco,p.Estoque
FROM dbo.Produtos p JOIN dbo.Categorias c ON c.CategoriaID=p.CategoriaID WHERE p.Ativo=1;
GO
SELECT ProdutoID,Nome,Categoria,Preco,Estoque FROM dbo.vw_ProdutosAtivos WHERE Preco<500 ORDER BY Preco;
GO
CREATE OR ALTER VIEW dbo.vw_ResumoPedidos AS
SELECT p.PedidoID,p.ClienteID,c.Nome AS Cliente,p.DataPedido,p.StatusPedido,
       COUNT(i.ItemPedidoID) AS LinhasItens,COALESCE(SUM(i.Quantidade),0) AS Unidades,
       COALESCE(SUM(i.Quantidade*i.PrecoUnitario),0) AS ValorCalculado
FROM dbo.Pedidos p JOIN dbo.Clientes c ON c.ClienteID=p.ClienteID
LEFT JOIN dbo.ItensPedido i ON i.PedidoID=p.PedidoID
GROUP BY p.PedidoID,p.ClienteID,c.Nome,p.DataPedido,p.StatusPedido;
GO
SELECT PedidoID,Cliente,LinhasItens,Unidades,ValorCalculado
FROM dbo.vw_ResumoPedidos WHERE StatusPedido='Pago' ORDER BY ValorCalculado DESC;
GO
CREATE OR ALTER VIEW dbo.vw_ClientesSemPedidos AS
SELECT c.ClienteID,c.Nome,c.Cidade FROM dbo.Clientes c
LEFT JOIN dbo.Pedidos p ON p.ClienteID=c.ClienteID WHERE p.PedidoID IS NULL;
GO
SELECT ClienteID,Nome FROM dbo.vw_ClientesSemPedidos WHERE Cidade LIKE N'J%' ORDER BY Nome;
GO
CREATE OR ALTER FUNCTION dbo.fn_CalcularSubtotal (@Quantidade int,@PrecoUnitario decimal(10,2))
RETURNS decimal(22,2)
AS
BEGIN
    RETURN @Quantidade*@PrecoUnitario;
END;
GO
SELECT dbo.fn_CalcularSubtotal(3,12.90) AS SubtotalDireto;
SELECT ItemPedidoID,dbo.fn_CalcularSubtotal(Quantidade,PrecoUnitario) AS Subtotal
FROM dbo.ItensPedido ORDER BY ItemPedidoID;
GO
CREATE OR ALTER FUNCTION dbo.fn_PedidosPorCliente (@ClienteID int)
RETURNS TABLE AS RETURN (
    SELECT PedidoID,DataPedido,StatusPedido,ValorTotal FROM dbo.Pedidos WHERE ClienteID=@ClienteID
);
GO
SELECT PedidoID,StatusPedido,ValorTotal FROM dbo.fn_PedidosPorCliente(1) ORDER BY PedidoID;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ListarPedidosCliente @ClienteID int,@StatusPedido varchar(20)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PedidoID,ClienteID,Cliente,DataPedido,StatusPedido,LinhasItens,Unidades,ValorCalculado
    FROM dbo.vw_ResumoPedidos WHERE ClienteID=@ClienteID
    AND (@StatusPedido IS NULL OR StatusPedido=@StatusPedido) ORDER BY DataPedido DESC,PedidoID DESC;
END;
GO
EXEC dbo.sp_ListarPedidosCliente @ClienteID=1;
EXEC dbo.sp_ListarPedidosCliente @ClienteID=1,@StatusPedido='Pago';
GO
CREATE OR ALTER PROCEDURE dbo.sp_AtualizarPrecoProduto
    @ProdutoID int,@NovoPreco decimal(10,2),@LinhasAfetadas int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @LinhasAfetadas=0;
    IF @NovoPreco IS NULL OR @NovoPreco<=0 THROW 50001,N'O preço deve ser maior que zero.',1;
    UPDATE dbo.Produtos SET Preco=@NovoPreco WHERE ProdutoID=@ProdutoID;
    SET @LinhasAfetadas=@@ROWCOUNT;
    IF @LinhasAfetadas=0 THROW 50002,N'Produto não encontrado.',1;
END;
GO
DECLARE @Linhas int;
SELECT ProdutoID,Preco AS Antes FROM dbo.vw_ProdutosAtivos WHERE ProdutoID=1;
EXEC dbo.sp_AtualizarPrecoProduto 1,125,@Linhas OUTPUT;
SELECT ProdutoID,Preco AS Depois,@Linhas AS Linhas FROM dbo.vw_ProdutosAtivos WHERE ProdutoID=1;
BEGIN TRY
    EXEC dbo.sp_AtualizarPrecoProduto 99999,125,@Linhas OUTPUT;
    THROW 51010,N'Esperava erro de produto inexistente.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>50002 THROW;
    SELECT ERROR_NUMBER() AS ErroInexistente;
END CATCH;
BEGIN TRY
    EXEC dbo.sp_AtualizarPrecoProduto 1,0,@Linhas OUTPUT;
    THROW 51011,N'Esperava erro de preço inválido.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>50001 THROW;
    SELECT ERROR_NUMBER() AS ErroPreco;
END CATCH;
SELECT PedidoID,ValorTotal FROM dbo.fn_PedidosPorCliente(1) ORDER BY PedidoID;
SELECT v.PedidoID,v.ValorCalculado,SUM(dbo.fn_CalcularSubtotal(i.Quantidade,i.PrecoUnitario)) AS ValorFuncao
FROM dbo.vw_ResumoPedidos v JOIN dbo.ItensPedido i ON i.PedidoID=v.PedidoID
GROUP BY v.PedidoID,v.ValorCalculado ORDER BY v.PedidoID;
