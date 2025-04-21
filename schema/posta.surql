USE NS posta DB posta;

OPTION IMPORT;

DEFINE ANALYZER search
    TOKENIZERS
        class
    FILTERS
        lowercase, ascii, edgengram(3,35);

-- ------------------------------
-- TABLE: Author
-- ------------------------------

DEFINE TABLE Author SCHEMAFULL
    PERMISSIONS
        FOR update, delete WHERE id IS $auth.id
        FOR select FULL;

-- Allow anyone to `select` these values
DEFINE FIELD name ON Author TYPE string
    PERMISSIONS
        FOR update WHERE id IS $auth.id;
DEFINE FIELD about ON Author TYPE option<string>
    PERMISSIONS
        FOR update WHERE id IS $auth.id;

-- Restrict `select` to resource owner only
DEFINE FIELD email_address ON Author TYPE string
    ASSERT
        string::is::email($value)
    VALUE
        string::lowercase($value)
    PERMISSIONS
        FOR select, update WHERE id IS $auth.id;

-- No `select`
DEFINE FIELD pass ON Author TYPE string
    PERMISSIONS
        FOR update WHERE id IS $auth.id
        FOR select NONE;

DEFINE INDEX unique_author_email_address_index ON TABLE Author FIELDS email_address UNIQUE;
DEFINE INDEX author_name_search_index ON TABLE Author FIELDS name UNIQUE SEARCH ANALYZER search BM25 HIGHLIGHTS CONCURRENTLY;

-- Record User Access
-- https://surrealdb.com/docs/surrealql/statements/define/access/record
DEFINE ACCESS Author ON DATABASE TYPE RECORD
    SIGNIN (
        SELECT * FROM Author WHERE email IS $email AND crypto::argon2::compare(pass, $pass)
    )
    SIGNUP (
        CREATE Author CONTENT {
            name: $name,
            email_address: $email_address,
            pass: crypto::argon2::generate($pass),
        }
    );

DEFINE EVENT author_deleted ON TABLE Author WHEN $event IS "DELETE" THEN {
    -- Delete all `Post`s when the `Author` is deleted.
    --
    -- Edge tables `published` and `edited` will automatically be deleted when
    -- no connecting nodes exists.
    DELETE Post WHERE <-published<-Author.id IS $before.id;
};

-- ------------------------------
-- TABLE: Post
-- ------------------------------

DEFINE TABLE Post SCHEMAFULL PERMISSIONS FULL;

DEFINE FIELD body ON Post TYPE string;
DEFINE FIELD title ON Post TYPE string;

DEFINE INDEX body_search_index ON TABLE Post FIELDS body SEARCH ANALYZER search BM25 HIGHLIGHTS CONCURRENTLY;
DEFINE INDEX title_search_index ON TABLE Post FIELDS title SEARCH ANALYZER search BM25 HIGHLIGHTS CONCURRENTLY;

DEFINE FUNCTION fn::Post::new($body: string, $title: string, $tags: array<string>) -> object {
    LET $post = CREATE ONLY Post CONTENT {
        body: $body,
        title: $title,
    } RETURN AFTER;

    RELATE ($auth.id)->published->($post.id);

    FOR $tag IN $tags {
        LET $tag = string::lowercase($tag);
        -- Make new `Tag` if `$tag` doesn't exist
        IF (array::is_empty(SELECT * FROM Tag WHERE tag IS $tag)) {
            CREATE ONLY Tag CONTENT { tag: $tag };
        };

        LET $post_id = $post.id;
        LET $tag_id = (SELECT id FROM Tag WHERE tag IS $tag);

        RELATE $post_id->tagged->$tag_id;
    };

    RETURN $post;
} PERMISSIONS FULL;

DEFINE EVENT post_edited ON TABLE Post WHEN $event IS "UPDATE" THEN {
    IF array::is_empty(SELECT id FROM published WHERE in IS $auth.id AND out IS $value.id) {
        THROW "Cannot edit unowned resource";
    };

    RELATE ($auth.id)->edited->($value.id) CONTENT {
        diff_ops: value::diff($before, $after)
    };
};

DEFINE EVENT post_deleted ON TABLE Post WHEN $event IS "DELETE" THEN {
    IF array::is_empty(SELECT id FROM published WHERE in IS $auth.id AND out IS $value.id) {
        THROW "Cannot delete unowned resource";
    };

    DELETE tagged WHERE in IS $before.id;
};

-- ------------------------------
-- TABLE: Tag
-- ------------------------------

DEFINE TABLE Tag SCHEMAFULL PERMISSIONS FOR select, create, update FULL;

DEFINE FIELD tag ON Tag TYPE string
    PERMISSIONS
        FOR update NONE;

DEFINE INDEX unique_tag_index ON TABLE Tag FIELDS tag UNIQUE;

-- ------------------------------
-- TABLE: published
-- ------------------------------

DEFINE TABLE published TYPE RELATION IN Author OUT Post ENFORCED SCHEMAFULL
    PERMISSIONS
        FOR select FULL
        FOR create WHERE in IS $auth.id;

DEFINE FIELD date ON published TYPE datetime DEFAULT time::now() READONLY;

DEFINE INDEX unique_published_relationships ON published FIELDS in, out UNIQUE;

-- ------------------------------
-- TABLE: edited
-- ------------------------------

DEFINE TABLE edited TYPE RELATION IN Author OUT Post ENFORCED SCHEMAFULL
    PERMISSIONS
        FOR create, select WHERE in IS $auth.id;

DEFINE FIELD date ON edited TYPE datetime DEFAULT time::now() READONLY;
DEFINE FIELD diff_ops ON edited TYPE array<object>;

-- ------------------------------
-- TABLE: starred
-- ------------------------------

DEFINE TABLE starred TYPE RELATION IN Author OUT Post ENFORCED SCHEMAFULL
    PERMISSIONS
        FOR create, select WHERE in IS $auth.id;

DEFINE FIELD date ON starred TYPE datetime DEFAULT time::now() READONLY;

DEFINE INDEX unique_starred_relationships ON starred FIELDS in, out UNIQUE;

-- ------------------------------
-- TABLE: tagged
-- ------------------------------

DEFINE TABLE tagged TYPE RELATION IN Post OUT Tag ENFORCED SCHEMAFULL
    PERMISSIONS FOR create, select FULL;

DEFINE INDEX unique_tagged_relationships ON tagged FIELDS in, out UNIQUE;

DEFINE EVENT post_tagged ON TABLE tagged WHEN $event IS "CREATE" THEN {
    IF array::is_empty(SELECT * FROM published WHERE in IS $auth.id AND out IS $value.in) {
        THROW "Cannot tag posts you do not own!";
    };
};

-- ------------------------------
-- TABLE: subscribed
-- ------------------------------

DEFINE TABLE subscribed TYPE RELATION IN Author OUT Author ENFORCED SCHEMAFULL
    PERMISSIONS
        FOR create, delete WHERE in IS $auth.id
        FOR select FULL;

DEFINE INDEX unique_subscribed_relationships ON subscribed FIELDS in, out UNIQUE;
