/* ============================================================================
   File: 03_keli_reference_seed.sql
   Procedure: dbo.sp_EdataTableSetup
   Role in assembly:
   - Delegates Keli reference seeding to the shared Keli-owned helper proc.
   Why this file exists:
   - eData setup still needs a safe follow-up hook when Keli tables already
     exist, but the actual Keli table discovery and seeding rules now live with
     the Keli import module instead of being embedded here.
   Maintenance notes:
   - Keep this fragment as a thin delegation layer only.
   - The shared proc is intentionally optional so eData setup remains safe even
     when the Keli tool has never been deployed or imported in this database.
   ============================================================================ */
    -- -------------------------------------------------------------------------
    -- Section 5: Delegate Keli reference seeding to the shared helper proc
    -- The helper owns Keli table discovery, scope resolution, and insert rules.
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(N'dbo.sp_SeedScopedKeliReferences', N'P') IS NOT NULL
    BEGIN
        EXEC dbo.sp_SeedScopedKeliReferences
            @ImportedByUserId = @ImportedByUserId,
            @StateFips = @StateFips,
            @CountyFips = @CountyFips;
    END;
