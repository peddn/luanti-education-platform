//! The description of the interface is checked in as api/openapi.json,
//! because the Lua tests of the bridge and later the frontend read it.
//! This test fails when the file no longer matches the code.
//!
//! To write the file again:  scripts/update-openapi.sh

use std::path::PathBuf;

#[test]
fn the_checked_in_description_matches_the_code() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../api/openapi.json");
    let checked_in = std::fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("cannot read {}: {err}", path.display()));
    assert!(
        checked_in == lep_backend::app::openapi_json(),
        "api/openapi.json is out of date. Run scripts/update-openapi.sh and commit the result."
    );
}
