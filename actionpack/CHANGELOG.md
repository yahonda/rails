*   Introduce safer, more explicit params handling method with `params#expect` such that
    `params.expect(table: [ :attr ])` replaces `params.require(:table).permit(:attr)`

    Ensures params are filtered with consideration for the expected
    types of values, improving handling of params and avoiding ignorable
    errors caused by params tampering.

    ```ruby
    # If the url is altered to ?person=hacked
    # Before
    params.require(:person).permit(:name, :age, pets: [:name])
    # raises NoMethodError, causing a 500 and potential error reporting

    # After
    params.expect(person: [ :name, :age, pets: [[:name]] ])
    # raises ActionController::ParameterMissing, correctly returning a 400 error
    ```

    You may also notice the new double array `[[:name]]`. In order to
    declare when a param is expected to be an array of parameter hashes,
    this new double array syntax is used to explicitly declare an array.
    `expect` requires you to declare expected arrays in this way, and will
    ignore arrays that are passed when, for example, `pet: [:name]` is used.

    In order to preserve compatibility, `permit` does not adopt the new
    double array syntax and is therefore more permissive about unexpected
    types. Using `expect` everywhere is recommended.

    We suggest replacing `params.require(:person).permit(:name, :age)`
    with the direct replacement `params.expect(person: [:name, :age])`
    to prevent external users from manipulating params to trigger 500
    errors. A 400 error will be returned instead, using public/400.html

    Usage of `params.require(:id)` should likewise be replaced with
    `params.expect(:id)` which is designed to ensure that `params[:id]`
    is a scalar and not an array or hash, also requiring the param.

    ```ruby
    # Before
    User.find(params.require(:id)) # allows an array, altering behavior

    # After
    User.find(params.expect(:id)) # expect only returns non-blank permitted scalars (excludes Hash, Array, nil, "", etc)
    ```

    *Martin Emde*

*   System Testing: Disable Chrome's search engine choice by default in system tests.

    *glaszig*

*   Fix `Request#raw_post` raising `NoMethodError` when `rack.input` is `nil`.

    *Hartley McGuire*

*   Remove `racc` dependency by manually writing `ActionDispatch::Journey::Scanner`.

    *Gannon McGibbon*

*   Speed up `ActionDispatch::Routing::Mapper::Scope#[]` by merging frame hashes.

    *Gannon McGibbon*

*   Allow bots to ignore `allow_browser`.

    *Matthew Nguyen*

*   Deprecate drawing routes with multiple paths to make routing faster.
    You may use `with_options` or a loop to make drawing multiple paths easier.

    ```ruby
    # Before
    get "/users", "/other_path", to: "users#index"

    # After
    get "/users", to: "users#index"
    get "/other_path", to: "users#index"
    ```

    *Gannon McGibbon*

*   Make `http_cache_forever` use `immutable: true`

    *Nate Matykiewicz*

*   Add `config.action_dispatch.strict_freshness`.

    When set to `true`, the `ETag` header takes precedence over the `Last-Modified` header when both are present,
    as specified by RFC 7232, Section 6.

    Defaults to `false` to maintain compatibility with previous versions of Rails, but is enabled as part of
    Rails 8.0 defaults.

    *heka1024*

*   Support `immutable` directive in Cache-Control

    ```ruby
    expires_in 1.minute, public: true, immutable: true
    # Cache-Control: public, max-age=60, immutable
    ```

    *heka1024*

*   Add `:wasm_unsafe_eval` mapping for `content_security_policy`

    ```ruby
    # Before
    policy.script_src "'wasm-unsafe-eval'"

    # After
    policy.script_src :wasm_unsafe_eval
    ```

    *Joe Haig*

*   Add `display_capture` and `keyboard_map` in `permissions_policy`

    *Cyril Blaecke*

*   Add `connect` route helper.

    *Samuel Williams*

Please check [7-2-stable](https://github.com/rails/rails/blob/7-2-stable/actionpack/CHANGELOG.md) for previous changes.
