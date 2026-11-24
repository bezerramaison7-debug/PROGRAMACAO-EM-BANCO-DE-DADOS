USE LojaVirtual;
GO
CREATE OR ALTER VIEW dbo.vw_CatalogoPublico AS
SELECT ProdutoID,Nome,Preco,
       CASE WHEN Estoque>0 THEN N'Disponível' ELSE N'Indisponível' END AS Disponibilidade
FROM dbo.Produtos WHERE Ativo=1;
GO
IF DATABASE_PRINCIPAL_ID('rl_CatalogoLeitura') IS NULL CREATE ROLE rl_CatalogoLeitura;
IF DATABASE_PRINCIPAL_ID('usr_CatalogoTeste') IS NULL CREATE USER usr_CatalogoTeste WITHOUT LOGIN;
IF NOT EXISTS (
    SELECT 1 FROM sys.database_role_members
    WHERE role_principal_id=DATABASE_PRINCIPAL_ID('rl_CatalogoLeitura')
    AND member_principal_id=DATABASE_PRINCIPAL_ID('usr_CatalogoTeste')
) ALTER ROLE rl_CatalogoLeitura ADD MEMBER usr_CatalogoTeste;
GRANT SELECT ON dbo.vw_CatalogoPublico TO rl_CatalogoLeitura;
DENY SELECT ON dbo.Produtos TO rl_CatalogoLeitura;
GO
CREATE OR ALTER PROCEDURE dbo.sp_BuscarProdutoSeguro @Termo nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    IF NULLIF(LTRIM(RTRIM(@Termo)),N'') IS NULL THROW 50050,N'Informe um termo de busca.',1;
    DECLARE @Filtro nvarchar(202)=N'%'+@Termo+N'%';
    EXEC sys.sp_executesql
        N'SELECT ProdutoID,Nome,Preco,Disponibilidade
          FROM dbo.vw_CatalogoPublico WHERE Nome LIKE @Filtro ORDER BY Nome;',
        N'@Filtro nvarchar(202)',@Filtro=@Filtro;
END;
GO
GRANT EXECUTE ON dbo.sp_BuscarProdutoSeguro TO rl_CatalogoLeitura;
DECLARE @Contexto int=USER_ID();
EXECUTE AS USER='usr_CatalogoTeste';
BEGIN TRY
    SELECT ProdutoID,Nome,Preco,Disponibilidade FROM dbo.vw_CatalogoPublico ORDER BY ProdutoID;
    BEGIN TRY
        SELECT ProdutoID,Nome,Estoque FROM dbo.Produtos;
        THROW 51060,N'O papel não deveria consultar a tabela.',1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER()<>229 THROW;
        SELECT ERROR_NUMBER() AS ErroAcessoDireto;
    END CATCH;
    EXEC dbo.sp_BuscarProdutoSeguro N'Mouse';
    EXEC dbo.sp_BuscarProdutoSeguro N'd''água';
    BEGIN TRY
        EXEC dbo.sp_BuscarProdutoSeguro N' ';
        THROW 51061,N'A busca deveria rejeitar o parâmetro vazio.',1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER()<>50050 THROW;
        SELECT ERROR_NUMBER() AS ErroTermoVazio;
    END CATCH;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;
REVERT;
IF USER_ID()<>@Contexto THROW 51062,N'O contexto de segurança não foi restaurado.',1;
SELECT CAST(1 AS bit) AS ContextoRestaurado;
GO
SELECT actual_state_desc,desired_state_desc,current_storage_size_mb,readonly_reason
FROM sys.database_query_store_options;
SELECT TOP (10) p.query_id,rs.count_executions,rs.avg_duration AS DuracaoMedia_us,
       rs.avg_cpu_time AS CpuMedia_us,rs.avg_logical_io_reads AS LeiturasLogicasMedias
FROM sys.query_store_runtime_stats rs JOIN sys.query_store_plan p ON p.plan_id=rs.plan_id
ORDER BY rs.avg_duration DESC;
GO
-- A coleta DMV durante uma requisição está no executor de testes de duas sessões.
