-- 00_create_database.sql
-- Creates the database. Run once.
IF DB_ID('FieldData') IS NULL
    CREATE DATABASE FieldData;
GO
