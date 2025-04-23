#!/usr/bin/env nu

use std/testing *
use ./testing.nu *
use ./utils.nu [surrealdb_setup, surrealdb_teardown, make_random_authors, send_query]

use std assert

@test
export def deletion_cleanup [] {
    let database = surrealdb_setup

    let authors = $database.bind | make_random_authors 2 | each {|it| $it | insert bind ($database | get bind)}

    let post = {
        query: "fn::Post::new($body, $title, $tags)"
        args: {
            body: (random chars)
            title: (random chars)
            tags: ([(random chars)] | to json)
        }} | send_query $authors.0 | get result | first

    { query: "RELATE ($auth.id)->subscribed->(SELECT id FROM Author WHERE name IS $name)"
        args: { name: ($authors.0 | get name) }} | send_query $authors.1

    { query: "RELATE ($auth.id)->starred->$post"
        args: {
            post: ($post | get id)
        }}
        | send_query $authors.1

    let queries = [[query];
        [$"SELECT * FROM Author WHERE name IS '($authors.0 | get name)'"]
        ["SELECT * FROM Post"]
        ["SELECT * FROM published"]
        ["SELECT * FROM subscribed"]
        ["SELECT * FROM tagged"]
        ["SELECT * FROM starred"]
    ]

    $queries | insert expected_length 1 | check_length $authors.1

    let deleted = { query: "DELETE $auth.id" args: {}} | send_query $authors.0 | first

    assert equal $deleted.status "OK"

    $queries | insert expected_length 0 | check_length $authors.1

    surrealdb_teardown
}

@test
export def update_info [] {
    let database = surrealdb_setup

    let authors = $database.bind | make_random_authors 2
    let about = random chars

    let updated_about = {
        query: "UPDATE $auth.id MERGE {about: $about}"
        args: {
            about: $about
        }}
        | send_query ($authors.0 | merge ($database | select bind))
        | first

    assert equal $updated_about.status "OK"
    assert equal ($updated_about | get result | first | get about) $about

    let invalid_updated = {
        query: "UPDATE $auth.id MERGE {name: $name}"
        args: {
            name: ($authors.1 | get name)
        }}
        | send_query ($authors.0 | merge ($database | select bind))
        | first

    assert equal $invalid_updated.status "ERR"
    assert (
        $invalid_updated.result
        | str contains "Database index `unique_author_name_index` already contains"
    )

    surrealdb_teardown
}

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

def check_length [database: record]: table<query: string, expected_length: int> -> any {
    $in
        | each {|check|
            {query: $check.query, args: {}}
                | send_query $database
                | first
                | assert length $in.result $check.expected_length
        }
}

