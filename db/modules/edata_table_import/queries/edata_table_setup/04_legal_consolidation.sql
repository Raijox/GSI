/* ============================================================================
   File: 04_legal_consolidation.sql
   Procedure: dbo.sp_EdataTableSetup
   Role in assembly:
   - Reserved legacy migration slot for older legal-table shapes.
   Why this file exists:
   - The new app's import path writes legal rows directly into dbo.gdi_legals, so
     the expensive legacy gdi_legal -> gdi_legals consolidation pass is not part
     of the normal import/setup workflow anymore.
   Maintenance notes:
   - Leave the modern import flow alone here.
   - If a future admin/addon tool needs to migrate historical dbo.gdi_legal rows,
     that work should live in that dedicated tool instead of slowing every setup.
   ============================================================================ */
    -- -------------------------------------------------------------------------
    -- Section 6: Legacy legal consolidation intentionally skipped
    -- -------------------------------------------------------------------------
    -- New-app imports already build dbo.gdi_legals directly during
    -- dbo.sp_GenericDataImport. We do not migrate dbo.gdi_legal rows here.
