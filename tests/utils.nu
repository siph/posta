export const DATABASE = {
    ns: "posta"
    db: "posta"
    ac: "Author"
    name: "bapa"
    email_address: "bapa@bapa.com"
    pass: "bapa"
}

export def surrealdb_setup []: nothing -> record {
    # Make ten attempts to aquire an unused port
    #
    # This can possible fail by lsop not catching overlapping ports in time
    let bind = 0..9
        | each {|_| random int 8000..8888}
        | where (lsof $"-i:($it)" | is-empty)
        | first
        | $"127.0.0.1:($in)"

    job spawn {(
        surreal
            start
            memory
            --allow-all
            --import-file ./schema/posta.surql
            --user $DATABASE.name
            --pass $DATABASE.pass
            --bind $bind
    )};

    sleep 1sec;

    http post --content-type application/json $"http://($bind)/signup" $DATABASE;

    $DATABASE | merge {bind: $bind}
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

export def new_user [bind: string]: nothing -> record {
    let new_user = {
        name: "talmbout"
        email_address: "talmbout@talmbout.com"
        pass: "talmbout"
    } | merge ($DATABASE | select ns db ac)

    http post --content-type application/json $"http://($bind)/signup" $new_user

    $new_user
}
