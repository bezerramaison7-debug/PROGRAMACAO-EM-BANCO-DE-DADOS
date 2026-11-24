USE LojaVirtual;
GO
SET NOCOUNT ON;
-- Etapa 1: localização, faixa, estoque e status.
SELECT Nome,Estado FROM dbo.Clientes WHERE Estado='SP' ORDER BY Nome;
SELECT Nome FROM dbo.Clientes WHERE Nome LIKE N'%Aur%' ORDER BY Nome;
SELECT Nome,Preco FROM dbo.Produtos WHERE Ativo=1 AND Preco BETWEEN 50 AND 500 ORDER BY Preco DESC;
SELECT Nome,Estoque FROM dbo.Produtos WHERE Estoque<10 ORDER BY Estoque,Nome;
SELECT DISTINCT StatusPedido FROM dbo.Pedidos
WHERE StatusPedido IN ('Pendente','Pago','Cancelado') ORDER BY StatusPedido;

-- Etapa 2: relacionamentos.
SELECT p.Nome,c.Nome AS Categoria FROM dbo.Produtos p
INNER JOIN dbo.Categorias c ON c.CategoriaID=p.CategoriaID ORDER BY p.ProdutoID;
SELECT p.PedidoID,c.Nome,c.Email FROM dbo.Pedidos p
INNER JOIN dbo.Clientes c ON c.ClienteID=p.ClienteID ORDER BY p.PedidoID;
SELECT i.PedidoID,p.Nome,i.Quantidade,i.PrecoUnitario,i.Quantidade*i.PrecoUnitario AS Subtotal
FROM dbo.ItensPedido i INNER JOIN dbo.Produtos p ON p.ProdutoID=i.ProdutoID ORDER BY i.ItemPedidoID;
SELECT c.Nome,p.PedidoID,p.DataPedido FROM dbo.Clientes c
LEFT JOIN dbo.Pedidos p ON p.ClienteID=c.ClienteID ORDER BY c.Nome,p.DataPedido;

-- Etapa 3: agregações.
SELECT (SELECT COUNT(*) FROM dbo.Clientes) AS Clientes,
       (SELECT COUNT(*) FROM dbo.Produtos) AS Produtos,
       (SELECT COUNT(*) FROM dbo.Pedidos) AS Pedidos;
SELECT MIN(Preco) AS Menor,MAX(Preco) AS Maior,AVG(Preco) AS Medio FROM dbo.Produtos WHERE Ativo=1;
SELECT c.Nome,COUNT(p.ProdutoID) AS Produtos,AVG(p.Preco) AS PrecoMedio
FROM dbo.Categorias c LEFT JOIN dbo.Produtos p ON p.CategoriaID=c.CategoriaID GROUP BY c.Nome ORDER BY Produtos DESC;
SELECT c.Nome,COUNT(p.PedidoID) AS Pedidos,
       SUM(CASE WHEN p.StatusPedido='Pago' THEN p.ValorTotal ELSE 0 END) AS TotalPago
FROM dbo.Clientes c LEFT JOIN dbo.Pedidos p ON p.ClienteID=c.ClienteID GROUP BY c.Nome ORDER BY TotalPago DESC;
SELECT c.Nome,COUNT(*) AS Produtos FROM dbo.Categorias c
JOIN dbo.Produtos p ON p.CategoriaID=c.CategoriaID GROUP BY c.Nome HAVING COUNT(*)>1 ORDER BY Produtos DESC;

-- Etapa 4: subconsultas, existência e classificação.
SELECT Nome,Preco FROM dbo.Produtos WHERE Preco>(SELECT AVG(Preco) FROM dbo.Produtos) ORDER BY Preco DESC;
SELECT c.Nome FROM dbo.Clientes c WHERE EXISTS
    (SELECT 1 FROM dbo.Pedidos p WHERE p.ClienteID=c.ClienteID) ORDER BY c.Nome;
SELECT PedidoID,ValorTotal FROM dbo.Pedidos
WHERE ValorTotal=(SELECT MAX(ValorTotal) FROM dbo.Pedidos) ORDER BY PedidoID;
SELECT Nome,Estoque,CASE WHEN Estoque<5 THEN N'Crítico' WHEN Estoque<15 THEN N'Baixo'
       ELSE N'Adequado' END AS Situacao FROM dbo.Produtos ORDER BY Estoque,Nome;

-- Etapa 5: todos os pedidos registrados, inclusive pendentes.
SELECT c.Nome,COUNT(p.PedidoID) AS Pedidos,COALESCE(SUM(p.ValorTotal),0) AS TotalComprado,
       COALESCE(AVG(p.ValorTotal),0) AS MediaPedido
FROM dbo.Clientes c LEFT JOIN dbo.Pedidos p ON p.ClienteID=c.ClienteID
GROUP BY c.Nome ORDER BY TotalComprado DESC,c.Nome;
