#!/usr/bin/env nu

use std/testing *
use ./testing.nu *
use ./utils.nu [surrealdb_setup, surrealdb_teardown, new_user, send_query]

use std assert

@test
export def subscribed [] {
    let database = surrealdb_setup

    let jimmy = {
        name: "jimmy"
        email_address: "jimmy@jimmy.com"
        pass: "jimmy"
    } | merge ($database | select ns db ac)

    let bimmy = {
        name: "bimmy"
        email_address: "bimmy@bimmy.com"
        pass: "bimmy"
    } | merge ($database | select ns db ac)

    [$bimmy, $jimmy]
        | each {|author|
            http post --content-type application/json $"http://($database.bind)/signup" $author
        }

    let subscribed = {
        query: "RELATE ($auth.id)->subscribed->(SELECT id FROM Author WHERE name IS $name)"
        args: {
            name: "jimmy"
        }}
        | send_query ($bimmy | merge ($database | select bind))
        | first

    assert equal $subscribed.status "OK"
    assert length $subscribed.result 1

    let duplicate_subscription = {
        query: "RELATE ($auth.id)->subscribed->(SELECT id FROM Author WHERE name IS $name)"
        args: {
            name: "jimmy"
        }}
        | send_query ($bimmy | merge ($database | select bind))
        | first

    assert equal $duplicate_subscription.status "ERR"

    surrealdb_teardown
}

@test
export def subscribed_auth [] {
    let database = surrealdb_setup

    let jimmy = {
        name: "jimmy"
        email_address: "jimmy@jimmy.com"
        pass: "jimmy"
    } | merge ($database | select ns db ac)

    let bimmy = {
        name: "bimmy"
        email_address: "bimmy@bimmy.com"
        pass: "bimmy"
    } | merge ($database | select ns db ac)

    [$bimmy, $jimmy]
        | each {|author|
            http post --content-type application/json $"http://($database.bind)/signup" $author
        }

    let subscribed = {
        query: "RELATE (SELECT id FROM Author WHERE name IS $name)->subscribed->($auth.id)"
        args: {
            name: "bimmy"
        }}
        | send_query ($jimmy | merge ($database | select bind))
        | first

    assert equal $subscribed.status "OK"
    assert length $subscribed.result 0

    surrealdb_teardown
}
