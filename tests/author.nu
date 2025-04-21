#!/usr/bin/env nu

use std/testing *
use ./testing.nu *
use ./utils.nu [surrealdb_setup, surrealdb_teardown, make_random_authors, send_query]

use std assert

@test
export def subscribed [] {
    let database = surrealdb_setup

    let authors = $database.bind | make_random_authors 2

    let subscribed = {
        query: "RELATE ($auth.id)->subscribed->(SELECT id FROM Author WHERE name IS $name)"
        args: {
            name: ($authors.0 | get name)
        }}
        | send_query ($authors.1 | merge ($database | select bind))
        | first

    assert equal $subscribed.status "OK"
    assert length $subscribed.result 1

    let duplicate_subscription = {
        query: "RELATE ($auth.id)->subscribed->(SELECT id FROM Author WHERE name IS $name)"
        args: {
            name: ($authors.0 | get name)
        }}
        | send_query ($authors.1 | merge ($database | select bind))
        | first

    assert equal $duplicate_subscription.status "ERR"
    assert (
        $duplicate_subscription.result
        | str contains "Database index `unique_subscribed_relationships` already contains"
    )

    surrealdb_teardown
}

@test
export def subscribed_auth [] {
    let database = surrealdb_setup

    let authors = $database.bind | make_random_authors 2

    let subscribed = {
        query: "RELATE (SELECT id FROM Author WHERE name IS $name)->subscribed->($auth.id)"
        args: {
            name: ($authors.1 | get name)
        }}
        | send_query ($authors.0 | merge ($database | select bind))
        | first

    assert equal $subscribed.status "OK"
    assert length $subscribed.result 0

    surrealdb_teardown
}
