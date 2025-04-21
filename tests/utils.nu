use std

export const DATABASE = {
    ns: "posta"
    db: "posta"
    ac: "Author"
    root_user: "posta"
    root_pass: "posta"
}

export def make_random_authors [count: int = 1]: string -> table {
    let bind = $in

    1..$count
        | each {|_| random chars }
        | each {|name|
            {
                name: $name
                email_address: $"($name)@($name).($name)"
                pass: $name
            } | merge ($DATABASE | select ns db ac)
        }
        | each {|author|
            http post --content-type application/json $"http://($bind)/signup" $author
            $author
        }
}

export def surrealdb_setup []: nothing -> record {
    let bind = ["127.0.0.1", (port | to text)] | str join ":"

    job spawn {(
        surreal
            start
            memory
            --allow-all
            --import-file ./schema/posta.surql
            --user ($DATABASE | get root_user)
            --pass ($DATABASE | get root_pass)
            --bind $bind
    )};

    sleep 1sec;

    $bind
        | make_random_authors
        | first
        | merge {bind: $bind}
}

export def surrealdb_teardown [] { job list | get id | each { |id| job kill $id } }

export def send_query [database: record]: record<args: record, query: string> -> list {
    let request = $in

    # Queries can have values passed as query parameters
    # https://surrealdb.com/docs/surrealdb/integration/http#sql
    let query_url = $"http://($database.bind)/sql"
        | if ($request.args | is-not-empty) {
            [$in, ($request.args | url build-query)] | str join "?"
        } else { $in }

    $request.query
        | (
            http
                post
                -e
                -H ({
                    Accept: "application/json"
                    Authorization: ([
                        "Bearer",
                        (
                            http
                                post
                                --headers {accept: application/json}
                                --content-type application/json
                                $"http://($database.bind)/signin"
                                ($database | select ns db ac email_address pass)
                            | get token
                        )] | str join " ")
                    surreal-ns: $database.ns
                    surreal-db: $database.db
                })
                $query_url
        )
}
