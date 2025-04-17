#!/usr/bin/env nu

use std/testing *
use ./testing.nu *
use ./utils.nu [surrealdb_setup, surrealdb_teardown, new_user, send_query]

use std assert

@test
export def starred_post [] {
    let database = surrealdb_setup

    let post = make_new_post $database | get result

    let star = {
        query: "RELATE ($auth.id)->starred->$post"
        args: {
            post: ($post | get id)
        }}
        | send_query $database
        | first

    assert equal $star.status "OK"

    let _duplicate_star = {
        query: "RELATE ($auth.id)->starred->$post"
        args: {
            post: ($post | get id)
        }}
        | send_query $database
        | first

    let starred = {
        query: "SELECT * FROM starred WHERE in IS $auth.id"
        args: {}}
        | send_query $database
        | first

    assert equal $starred.status "OK"
    assert length $starred.result 1

    surrealdb_teardown
}

@test
export def starred_post_auth [] {
    let database = surrealdb_setup

    let post = make_new_post $database | get result

    let new_user = new_user $database.bind

    let _unauthorized_starred = {
        query: "RELATE ((SELECT in FROM published).in)->starred->$post"
        args: {
            name: "bapa"
            post: ($post | get id)
        }}
        | send_query ($new_user | merge {bind: $database.bind})
        | first

    let starred = {
        query: "SELECT * FROM starred"
        args: {}}
        | send_query $database
        | first

    assert length $starred.result 0

    surrealdb_teardown
}

@test
export def delete_post [] {
    let database = surrealdb_setup

    let post = make_new_post $database | get result

    let tagged = {
        query: "SELECT * FROM tagged WHERE in IS $id"
        args: {
            id: $post.id
        }}
        | send_query $database
        | get result
        | first

    assert length $tagged 1

    let deleted = {
        query: "DELETE $id"
        args: {
            id: $post.id
        }}
        | send_query $database

    assert equal ($deleted | first | get status) "OK"

    let empty_tagged = {
        query: "SELECT * FROM Post"
        args: {}}
        | send_query $database
        | get result
        | first
    assert length $empty_tagged 0


    let empty_tagged = {
        query: "SELECT * FROM tagged WHERE in IS $id"
        args: {
            id: $post.id
        }}
        | send_query $database
        | get result
        | first
    assert length $empty_tagged 0

    surrealdb_teardown
}

@test
export def delete_post_auth [] {
    let database = surrealdb_setup

    let post = make_new_post $database | get result

    let new_user = new_user $database.bind

    let delete_error = {
        query: "DELETE $id"
        args: {
            id: $post.id
        }}
        | send_query ($new_user | merge {bind: $database.bind})
        | first

    assert equal $delete_error.status "ERR"
    assert equal $delete_error.result "An error occurred: Cannot delete unowned resource"

    surrealdb_teardown
}

@test
export def edit_post [] {
    let database = surrealdb_setup

    let post = make_new_post $database | get result

    let edit = {
        query: "UPDATE $id MERGE {body: $body}"
        args: {
            body: `"gimping is easy."`
            id: ($post | get id)
        }}
        | send_query $database
        | first

    assert equal $edit.status "OK"

    let edited = {
        query: "SELECT * FROM edited WHERE out IS $id"
        args: {id: ($post | get id)}
        }
        | send_query $database

    $edited
        | first
        | each {|it| assert equal $in.status "OK" ; $it }
        | get result
        | each {|result|
            assert equal ($result | get out) $post.id
            # TODO: idk why this isn't working (no diffs, just `[{}]`)
            # assert equal ($result | get diff_ops) [{op: "_", path: "_", value: "_"}]
        }

    surrealdb_teardown
}

@test
export def edit_post_auth [] {
    let database = surrealdb_setup

    let post = make_new_post $database | get result

    let new_user = new_user $database.bind

    let edit_error = {
        query: "UPDATE $id MERGE {body: $body}"
        args: {
            body: `"gimmie error"`
            id: ($post | get id)
        }}
        | send_query ($new_user | merge {bind: $database.bind})
        | first

    assert equal $edit_error.status "ERR"
    assert equal $edit_error.result "An error occurred: Cannot edit unowned resource"

    surrealdb_teardown
}

@test
export def publish_post [] {
    let database = surrealdb_setup

    let post = make_new_post $database

    assert equal $post.status "OK"
    assert equal $post.result.title "Sagelee"

    let tagged = {
        query: "SELECT * FROM tagged"
        args: {}}
        | send_query $database
        | first

    assert equal $tagged.status "OK"
    assert equal ($tagged.result | first | get in) $post.result.id

    let published = {
        query: "SELECT * FROM published"
        args: {}}
        | send_query $database
        | first

    assert equal $published.status "OK"
    assert equal ($published.result | first | get out) $post.result.id

    surrealdb_teardown
}

def make_new_post [database: record]: nothing -> record {
    {
        query: "fn::Post::new($body, $title, $tags)"
        args: {
            body: `"pimping isn't easy, but prostition is significantly harder"`
            title: `"Sagelee"`
            tags: ([`"advice"`] | to json)
        }
    }
        | send_query $database
        | first

}
