USE LojaVirtual;
GO
CREATE TABLE dbo.Pagamentos (
    PagamentoID int IDENTITY PRIMARY KEY,
    PedidoID int NOT NULL UNIQUE REFERENCES dbo.Pedidos(PedidoID),
    DataPagamento datetime2 NOT NULL DEFAULT SYSDATETIME(),
    ValorPago decimal(10,2) NOT NULL CHECK (ValorPago>0),
    FormaPagamento varchar(30) NOT NULL
);
GO
CREATE OR ALTER PROCEDURE dbo.sp_ProcessarPagamento @PedidoID int,@FormaPagamento varchar(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Status varchar(20),@Valor decimal(10,2);
        SELECT @Status=StatusPedido,@Valor=ValorTotal
        FROM dbo.Pedidos WITH (UPDLOCK,HOLDLOCK) WHERE PedidoID=@PedidoID;

        IF @Status IS NULL THROW 50010,N'Pedido não encontrado.',1;
        IF @Status<>'Pendente' THROW 50011,N'Pedido não está pendente.',1;
        IF NULLIF(LTRIM(RTRIM(@FormaPagamento)),'') IS NULL
            THROW 50012,N'Forma de pagamento obrigatória.',1;

        INSERT dbo.Pagamentos (PedidoID,ValorPago,FormaPagamento)
        VALUES (@PedidoID,@Valor,@FormaPagamento);
        UPDATE dbo.Pedidos SET StatusPedido='Pago' WHERE PedidoID=@PedidoID;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
SET NOCOUNT ON;
INSERT dbo.Pedidos (ClienteID,DataPedido,StatusPedido,ValorTotal)
VALUES (2,'20260501','Pendente',130);
INSERT dbo.ItensPedido (PedidoID,ProdutoID,Quantidade,PrecoUnitario) VALUES (8,1,1,130);
DECLARE @Antes int=(SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=1);
EXEC dbo.sp_ProcessarPagamento 2,'Pix';
SELECT p.PedidoID,p.StatusPedido,pg.ValorPago,@Antes AS EstoqueAntes,pr.Estoque AS EstoqueDepois
FROM dbo.Pedidos p JOIN dbo.Pagamentos pg ON pg.PedidoID=p.PedidoID
CROSS JOIN dbo.Produtos pr WHERE p.PedidoID=2 AND pr.ProdutoID=1;
IF NOT EXISTS (SELECT 1 FROM dbo.Pagamentos WHERE PedidoID=2 AND ValorPago=120)
OR (SELECT StatusPedido FROM dbo.Pedidos WHERE PedidoID=2)<>'Pago'
OR (SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=1)<>@Antes-1
    THROW 51030,N'COMMIT inconsistente.',1;
BEGIN TRY
    EXEC dbo.sp_ProcessarPagamento 99999,'Pix';
    THROW 51031,N'Pedido inexistente deveria falhar.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>50010 THROW;
    SELECT ERROR_NUMBER() AS ErroInexistente,@@TRANCOUNT AS Transacoes,XACT_STATE() AS Estado;
END CATCH;
BEGIN TRY
    EXEC dbo.sp_ProcessarPagamento 2,'Pix';
    THROW 51032,N'Pedido já pago deveria falhar.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>50011 THROW;
    SELECT ERROR_NUMBER() AS ErroJaPago,@@TRANCOUNT AS Transacoes,XACT_STATE() AS Estado;
END CATCH;
DECLARE @EstoqueInvalido int=(SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=2);
BEGIN TRY
    EXEC dbo.sp_ProcessarPagamento 5,'Pix';
    THROW 51033,N'Pedido sem estoque deveria falhar.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>50021 THROW;
    SELECT ERROR_NUMBER() AS ErroRollback,@@TRANCOUNT AS Transacoes,XACT_STATE() AS Estado;
END CATCH;
IF EXISTS (SELECT 1 FROM dbo.Pagamentos WHERE PedidoID=5)
OR (SELECT StatusPedido FROM dbo.Pedidos WHERE PedidoID=5)<>'Pendente'
OR (SELECT Estoque FROM dbo.Produtos WHERE ProdutoID=2)<>@EstoqueInvalido
    THROW 51034,N'ROLLBACK inconsistente.',1;
SELECT p.StatusPedido,pr.Estoque,(SELECT COUNT(*) FROM dbo.Pagamentos WHERE PedidoID=5) AS PagamentosParciais
FROM dbo.Pedidos p CROSS JOIN dbo.Produtos pr WHERE p.PedidoID=5 AND pr.ProdutoID=2;
DBCC USEROPTIONS WITH NO_INFOMSGS;
-- Pedido 8 é reservado para o teste de duas sessões.
