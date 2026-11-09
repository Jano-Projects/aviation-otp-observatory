create or replace package pkg_ref_load authid definer as
  /*
   * Loads airline and airport REFERENCE data from two staged sources and
   * copies names to the core dimensions.
   *
   * Precedence rules:
   *   airlines  ANAC only; for each ICAO code, the name of the most recent year.
   *   airports  ANAC gives the city, state, country and continent (Portuguese);
   *             OurAirports gives the official name, IATA code, ISO country and
   *             coordinates. An OurAirports row matches a code by icao_code first,
   *             then ident, then gps_code; among equals, larger airports win.
   *
   * Transaction contract: like pkg_vra_load, nothing here commits.
   */

  e_no_staged_rows exception;
  pragma exception_init(e_no_staged_rows, -20002);

  /*
   * '-23.435556' -> -23.435556 (rounded to 6 decimals), independent of the
   * session's decimal separator. NULL for anything that is not a plain number.
   */
  function to_coord(p_value in varchar2) return number deterministic;

  /*
   * Merges the staged reference files into REF_AIRLINE and REF_AIRPORT, then
   * calls sync_core. Returns the RUN_ID logged in CORE_LOAD_RUN.
   * Raises ORA-20002 unless both files have staged rows.
   */
  function process_reference(
    p_anac_file  in varchar2,
    p_oa_file    in varchar2
  ) return number;

  /*
   * Copies reference names onto CORE_AIRLINE and CORE_AIRPORT (codes already
   * there only). Safe to call after every VRA load. Returns rows updated.
   */
  function sync_core return pls_integer;

end pkg_ref_load;
/
