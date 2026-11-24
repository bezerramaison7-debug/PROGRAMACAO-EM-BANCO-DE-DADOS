USE master;
GO
IF DB_ID(N'LojaVirtual') IS NOT NULL
    THROW 51000, N'Use uma instância de laboratório sem o banco LojaVirtual.', 1;
GO
CREATE DATABASE LojaVirtual;
GO
USE LojaVirtual;
GO
SET NOCOUNT ON;
CREATE TABLE dbo.Clientes (
    ClienteID int IDENTITY PRIMARY KEY,
    Nome nvarchar(100) NOT NULL,
    Email varchar(150) NOT NULL UNIQUE,
    Cidade nvarchar(80) NOT NULL,
    Estado char(2) NOT NULL,
    DataCadastro date NOT NULL DEFAULT CONVERT(date,SYSDATETIME())
);
CREATE TABLE dbo.Categorias (
    CategoriaID int IDENTITY PRIMARY KEY,
    Nome nvarchar(80) NOT NULL UNIQUE
);
CREATE TABLE dbo.Produtos (
    ProdutoID int IDENTITY PRIMARY KEY,
    CategoriaID int NOT NULL REFERENCES dbo.Categorias(CategoriaID),
    Nome nvarchar(100) NOT NULL,
    Preco decimal(10,2) NOT NULL CHECK (Preco >= 0),
    Estoque int NOT NULL CHECK (Estoque >= 0),
    Ativo bit NOT NULL DEFAULT 1
);
CREATE TABLE dbo.Pedidos (
    PedidoID int IDENTITY PRIMARY KEY,
    ClienteID int NOT NULL REFERENCES dbo.Clientes(ClienteID),
    DataPedido datetime2(0) NOT NULL DEFAULT SYSDATETIME(),
    StatusPedido varchar(20) NOT NULL CHECK (StatusPedido IN ('Pendente','Pago','Cancelado')),
    ValorTotal decimal(10,2) NOT NULL CHECK (ValorTotal >= 0)
);
CREATE TABLE dbo.ItensPedido (
    ItemPedidoID int IDENTITY PRIMARY KEY,
    PedidoID int NOT NULL REFERENCES dbo.Pedidos(PedidoID),
    ProdutoID int NOT NULL REFERENCES dbo.Produtos(ProdutoID),
    Quantidade int NOT NULL CHECK (Quantidade > 0),
    PrecoUnitario decimal(10,2) NOT NULL CHECK (PrecoUnitario >= 0)
);
INSERT dbo.Categorias (Nome) VALUES (N'Eletrônicos'),(N'Casa'),(N'Papelaria');
INSERT dbo.Clientes (Nome,Email,Cidade,Estado) VALUES
    (N'Cliente Aurora','aurora@example.invalid',N'Campinas','SP'),
    (N'Cliente Brisa','brisa@example.invalid',N'Curitiba','PR'),
    (N'Cliente Cedro','cedro@example.invalid',N'Santos','SP');
INSERT dbo.Produtos (CategoriaID,Nome,Preco,Estoque) VALUES
    (1,N'Teclado',120,30),(1,N'Mouse',80,4),(1,N'Monitor',700,9),
    (2,N'Luminária',60,0),(2,N'Garrafa d''água',35,18),(3,N'Caderno',25,10);
INSERT dbo.Pedidos (ClienteID,DataPedido,StatusPedido,ValorTotal) VALUES
    (1,'20260115','Pago',200),(1,'20260203','Pendente',120),(2,'20260302','Pago',85);
INSERT dbo.ItensPedido (PedidoID,ProdutoID,Quantidade,PrecoUnitario) VALUES
    (1,1,1,120),(1,2,1,80),(2,1,1,120),(3,5,1,35),(3,6,2,25);

-- Consultas de conferência.
SELECT ClienteID,Nome,Cidade,Estado FROM dbo.Clientes ORDER BY Nome;
SELECT ProdutoID,Nome,Preco FROM dbo.Produtos WHERE Ativo=1 AND Preco<500 ORDER BY Preco;
SELECT p.Nome,c.Nome AS Categoria,p.Preco,p.Estoque FROM dbo.Produtos p
JOIN dbo.Categorias c ON c.CategoriaID=p.CategoriaID ORDER BY p.ProdutoID;
SELECT p.PedidoID,c.Nome,p.StatusPedido,p.ValorTotal FROM dbo.Pedidos p
JOIN dbo.Clientes c ON c.ClienteID=p.ClienteID ORDER BY p.PedidoID;
SELECT i.PedidoID,p.Nome,i.Quantidade*i.PrecoUnitario AS Subtotal
FROM dbo.ItensPedido i JOIN dbo.Produtos p ON p.ProdutoID=i.ProdutoID ORDER BY i.ItemPedidoID;
SELECT ClienteID,SUM(ValorTotal) AS TotalPedidos FROM dbo.Pedidos GROUP BY ClienteID;

SELECT ProdutoID,Preco,Estoque,Ativo FROM dbo.Produtos WHERE ProdutoID IN (1,5,6) ORDER BY ProdutoID;
SELECT ClienteID,Cidade FROM dbo.Clientes WHERE ClienteID=3;
UPDATE dbo.Produtos SET Estoque=Estoque+10 WHERE ProdutoID=1;
UPDATE dbo.Produtos SET Preco=39.90 WHERE ProdutoID=5;
UPDATE dbo.Clientes SET Cidade=N'Jundiaí' WHERE ClienteID=3;
UPDATE dbo.Produtos SET Ativo=0 WHERE ProdutoID=6;
SELECT ProdutoID,Preco,Estoque,Ativo FROM dbo.Produtos WHERE ProdutoID IN (1,5,6) ORDER BY ProdutoID;
SELECT ClienteID,Cidade FROM dbo.Clientes WHERE ClienteID=3;
SELECT PrecoUnitario AS PrecoHistorico FROM dbo.ItensPedido WHERE ProdutoID=5;

INSERT dbo.Clientes (Nome,Email,Cidade,Estado)
VALUES (N'Cliente Removível','remover@example.invalid',N'Teste','SP');
SELECT ClienteID,Nome FROM dbo.Clientes WHERE Email='remover@example.invalid';
DELETE dbo.Clientes WHERE Email='remover@example.invalid';
SELECT @@ROWCOUNT AS QuantidadeExcluida;
IF EXISTS (
    SELECT 1 FROM dbo.Pedidos p JOIN dbo.ItensPedido i ON i.PedidoID=p.PedidoID
    GROUP BY p.PedidoID,p.ValorTotal HAVING SUM(i.Quantidade*i.PrecoUnitario)<>p.ValorTotal
) THROW 51001,N'Total inicial divergente.',1;

BEGIN TRY
    UPDATE dbo.Produtos SET Estoque=-1 WHERE ProdutoID=1;
    THROW 51002,N'CHECK deveria rejeitar estoque negativo.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>547 THROW;
    SELECT ERROR_NUMBER() AS ErroCheck;
END CATCH;
BEGIN TRY
    INSERT dbo.ItensPedido (PedidoID,ProdutoID,Quantidade,PrecoUnitario) VALUES (99999,1,1,120);
    THROW 51003,N'FK deveria rejeitar pedido inexistente.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>547 THROW;
    SELECT ERROR_NUMBER() AS ErroFK;
END CATCH;
BEGIN TRY
    INSERT dbo.Clientes (Nome,Email,Cidade,Estado) VALUES (N'Duplicado','aurora@example.invalid',N'Teste','SP');
    THROW 51004,N'UNIQUE deveria rejeitar email duplicado.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() NOT IN (2601,2627) THROW;
    SELECT ERROR_NUMBER() AS ErroUnique;
END CATCH;
SELECT (SELECT COUNT(*) FROM dbo.Clientes) AS Clientes,
       (SELECT COUNT(*) FROM dbo.Categorias) AS Categorias,
       (SELECT COUNT(*) FROM dbo.Produtos) AS Produtos,
       (SELECT COUNT(*) FROM dbo.Pedidos) AS Pedidos,
       (SELECT COUNT(*) FROM dbo.ItensPedido) AS Itens;
