#!/usr/bin/env nu

use ./testing.nu run-tests
use ./utils.nu surrealdb_teardown

def main [] {
    try { run-tests } catch { |err| surrealdb_teardown ; error make $err }
    ()
}

