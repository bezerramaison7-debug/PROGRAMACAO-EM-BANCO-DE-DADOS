USE LojaVirtual;
GO
CREATE TABLE dbo.AlertasEstoque (
    AlertaID int IDENTITY PRIMARY KEY,
    ProdutoID int NOT NULL REFERENCES dbo.Produtos(ProdutoID),
    DataAlerta datetime2 NOT NULL DEFAULT SYSDATETIME(),
    NivelAlerta varchar(20) NOT NULL,
    Mensagem nvarchar(200) NOT NULL
);
GO
CREATE OR ALTER PROCEDURE dbo.sp_GerarAlertasCursor @SimularErro bit=0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ProdutoID int,@Nome nvarchar(100),@Estoque int,@Nivel varchar(20);
    DECLARE cur_Estoque CURSOR LOCAL FAST_FORWARD FOR
        SELECT ProdutoID,Nome,Estoque FROM dbo.Produtos WHERE Estoque<=5 ORDER BY ProdutoID;
    BEGIN TRY
        OPEN cur_Estoque;
        FETCH NEXT FROM cur_Estoque INTO @ProdutoID,@Nome,@Estoque;
        WHILE @@FETCH_STATUS=0
        BEGIN
            IF @SimularErro=1 THROW 50040,N'Falha de laboratório após abrir o cursor.',1;
            IF @Estoque=0 SET @Nivel='URGENTE';
            ELSE SET @Nivel='ATENCAO';
            INSERT dbo.AlertasEstoque (ProdutoID,NivelAlerta,Mensagem)
            VALUES (@ProdutoID,@Nivel,CONCAT(N'Produto ',@Nome,N': estoque atual = ',@Estoque,N'.'));
            FETCH NEXT FROM cur_Estoque INTO @ProdutoID,@Nome,@Estoque;
        END;
        CLOSE cur_Estoque;
        DEALLOCATE cur_Estoque;
        SELECT CURSOR_STATUS('local','cur_Estoque') AS CursorAposSucesso;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local','cur_Estoque')>=0 CLOSE cur_Estoque;
        IF CURSOR_STATUS('local','cur_Estoque')>=-1 DEALLOCATE cur_Estoque;
        SELECT CURSOR_STATUS('local','cur_Estoque') AS CursorAposFalha;
        THROW;
    END CATCH;
END;
GO
SET NOCOUNT ON;
SELECT ProdutoID,Nome,Estoque FROM dbo.Produtos ORDER BY ProdutoID;
BEGIN TRY
    EXEC dbo.sp_GerarAlertasCursor @SimularErro=1;
    THROW 51040,N'Falha controlada não foi gerada.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>50040 THROW;
    SELECT ERROR_NUMBER() AS ErroControlado,CURSOR_STATUS('local','cur_Estoque') AS CursorExterno;
END CATCH;
DECLARE @Inicio datetime2(7)=SYSDATETIME();
SET STATISTICS TIME ON;
EXEC dbo.sp_GerarAlertasCursor;
SET STATISTICS TIME OFF;
SELECT DATEDIFF_BIG(microsecond,@Inicio,SYSDATETIME()) AS CursorMicrossegundos;
SELECT ProdutoID,NivelAlerta,Mensagem INTO #Cursor FROM dbo.AlertasEstoque;
DELETE FROM dbo.AlertasEstoque WHERE AlertaID>0;

SET @Inicio=SYSDATETIME();
SET STATISTICS TIME ON;
INSERT dbo.AlertasEstoque (ProdutoID,NivelAlerta,Mensagem)
SELECT ProdutoID,CASE WHEN Estoque=0 THEN 'URGENTE' ELSE 'ATENCAO' END,
       CONCAT(N'Produto ',Nome,N': estoque atual = ',Estoque,N'.')
FROM dbo.Produtos WHERE Estoque<=5;
SET STATISTICS TIME OFF;
SELECT DATEDIFF_BIG(microsecond,@Inicio,SYSDATETIME()) AS ConjuntoMicrossegundos;
IF (SELECT COUNT(*) FROM #Cursor)<>(SELECT COUNT(*) FROM dbo.AlertasEstoque)
OR EXISTS (SELECT ProdutoID,NivelAlerta,Mensagem FROM #Cursor
           EXCEPT SELECT ProdutoID,NivelAlerta,Mensagem FROM dbo.AlertasEstoque)
OR EXISTS (SELECT ProdutoID,NivelAlerta,Mensagem FROM dbo.AlertasEstoque
           EXCEPT SELECT ProdutoID,NivelAlerta,Mensagem FROM #Cursor)
    THROW 51041,N'As abordagens geraram alertas diferentes.',1;

SELECT ProdutoID,NivelAlerta,Mensagem FROM dbo.AlertasEstoque ORDER BY ProdutoID;
DECLARE @Urgentes int=(SELECT COUNT(*) FROM dbo.AlertasEstoque WHERE NivelAlerta='URGENTE'),
        @Atencao int=(SELECT COUNT(*) FROM dbo.AlertasEstoque WHERE NivelAlerta='ATENCAO');
IF @Urgentes>0 PRINT N'Há itens urgentes.';
ELSE PRINT N'Nenhum item urgente.';
SELECT @Urgentes AS Urgentes,@Atencao AS Atencao,
       CASE WHEN @Urgentes>0 THEN N'Alto' WHEN @Atencao>0 THEN N'Médio' ELSE N'Baixo' END AS Risco;
DROP TABLE #Cursor;
