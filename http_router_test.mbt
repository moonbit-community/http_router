///|
async fn dummy_handler(
  _req : @http.Request,
  _body : &@io.Reader,
  conn : @http.ServerConnection,
  _params : Params,
) -> Unit {
  conn.send_response(200, "OK") |> ignore
  conn.end_response()
}

///|
async fn bench_lookup(
  router : Router,
  method_name : String,
  path : String,
  n : Int,
) -> Unit {
  let start = @async.now()
  for _ in 0..<n {
    let (h, params, _) = router.lookup(method_name, path)
    ignore(h)
    ignore(params)
  }
  let end = @async.now()
  let elapsed = end - start
  let elapsed_ms = elapsed.to_int()
  let throughput = if elapsed_ms > 0 { n * 1000 / elapsed_ms } else { 0 }
  println(
    "bench_lookup method=\{method_name} path=\{path} n=\{n} elapsed_ms=\{elapsed} rps=\{throughput}",
  )
}

///|
fn bench_lookup_paths(
  router : Router,
  method_name : String,
  paths : Array[String],
  n : Int,
) -> Unit raise {
  guard not(paths.is_empty()) else {
    abort("bench_lookup_paths needs at least one path")
  }
  let start = @async.now()
  for i in 0..<n {
    let path = paths[i % paths.length()]
    let (h, params, _) = router.lookup(method_name, path)
    ignore(h)
    ignore(params)
  }
  let elapsed = @async.now() - start
  let elapsed_ms = elapsed.to_int()
  let throughput = if elapsed_ms > 0 { n * 1000 / elapsed_ms } else { 0 }
  println(
    "bench_lookup_paths method=\{method_name} routes=\{paths.length()} n=\{n} elapsed_ms=\{elapsed} rps=\{throughput}",
  )
}

///|
async test "bench simple routes" {
  let router = Router::new()
  router.get("/", dummy_handler)
  router.get("/hello", dummy_handler)
  router.get("/user/:id", dummy_handler)
  router.get("/static/file", dummy_handler)
  bench_lookup(router, "GET", "/", 100000)
  bench_lookup(router, "GET", "/hello", 100000)
  bench_lookup(router, "GET", "/user/12345", 100000)
  bench_lookup(router, "GET", "/static/file", 100000)
}

///|
async test "bench many params" {
  let router = Router::new()
  router.get("/:a/:b/:c/:d/:e/:f/:g/:h/:i/:j", dummy_handler)
  bench_lookup(router, "GET", "/1/2/3/4/5/6/7/8/9/10", 100000)
}

///|
async test "head fallback to get handler" {
  let router = Router::new()
  router.get("/users/:id", dummy_handler)
  let (head_handle, params, _) = router.lookup("HEAD", "/users/42")
  assert_eq(head_handle is Some(_), true)
  assert_eq(by_name(params, "id"), "42")
}

///|
async test "test params extraction" {
  let router = Router::new()
  router.get("/user/:id", dummy_handler)
  let (_, params, _) = router.lookup("GET", "/user/123")
  assert_eq(params.length(), 1)
  assert_eq(by_name(params, "id"), "123")
}

///|
async test "test catch-all" {
  let router = Router::new()
  router.get("/static/*filepath", dummy_handler)
  let (_, params, _) = router.lookup("GET", "/static/css/style.css")
  assert_eq(params.length(), 1)
  assert_eq(by_name(params, "filepath"), "css/style.css")
}

///|
async test "test multiple methods" {
  let router = Router::new()
  router.get("/api/users", dummy_handler)
  router.post("/api/users", dummy_handler)
  router.put("/api/users/:id", dummy_handler)
  router.delete("/api/users/:id", dummy_handler)
  let (get_handle, _, _) = router.lookup("GET", "/api/users")
  assert_eq(get_handle is Some(_), true)
  let (post_handle, _, _) = router.lookup("POST", "/api/users")
  assert_eq(post_handle is Some(_), true)
  let (put_handle, params, _) = router.lookup("PUT", "/api/users/123")
  assert_eq(put_handle is Some(_), true)
  assert_eq(by_name(params, "id"), "123")
  let (delete_handle, params2, _) = router.lookup("DELETE", "/api/users/456")
  assert_eq(delete_handle is Some(_), true)
  assert_eq(by_name(params2, "id"), "456")
}

///|
async test "bench massive static routes" {
  let router = Router::new()
  for i in 0..<2000 {
    router.get("/static/data/\{i}", dummy_handler)
  }
  bench_lookup(router, "GET", "/static/data/0", 200000)
  bench_lookup(router, "GET", "/static/data/1999", 200000)
}

///|
async test "bench realistic mixed workload" {
  let router = Router::new()
  router.get("/", dummy_handler)
  router.get("/user/:id", dummy_handler)
  router.get("/user/:id/profile", dummy_handler)
  router.get("/user/:id/settings", dummy_handler)
  router.get("/posts/:category/:id", dummy_handler)
  router.get("/posts/:category/:id/comments", dummy_handler)
  router.get("/files/*filepath", dummy_handler)
  router.get("/admin/:section/:page", dummy_handler)
  let paths = [
    "/", "/user/123", "/user/123/profile", "/user/123/settings", "/posts/tech/42",
    "/posts/tech/42/comments", "/files/assets/js/app.js", "/files/docs/guide.pdf",
    "/admin/settings/overview",
  ]
  bench_lookup_paths(router, "GET", paths, 200000)
}

///|
async test "bench catch-all heavy" {
  let router = Router::new()
  router.get("/assets/*filepath", dummy_handler)
  router.get("/assets/images/*filepath", dummy_handler)
  router.get("/assets/js/*filepath", dummy_handler)
  router.get("/assets/css/*filepath", dummy_handler)
  let paths = [
    "/assets/js/app.js", "/assets/css/style.css", "/assets/images/logo.png", "/assets/readme.txt",
  ]
  bench_lookup_paths(router, "GET", paths, 150000)
}

///|
async test "test trailing slash redirect" {
  let router = Router::new()
  router.get("/users", dummy_handler)
  router.get("/posts/", dummy_handler)
  let (path1, code1) = router.try_redirect("GET", "/users/")
  assert_eq(path1 is Some(_), true)
  assert_eq(code1, 301)
  let (path2, code2) = router.try_redirect("GET", "/posts")
  assert_eq(path2 is Some(_), true)
  assert_eq(code2, 301)
  let (path3, code3) = router.try_redirect("GET", "/notfound/")
  assert_eq(path3 is None, true)
  assert_eq(code3, 0)
}

///|
async test "test case insensitive path fix" {
  let router = Router::new()
  router.get("/Users/Profile", dummy_handler)
  router.get("/Posts/Show", dummy_handler)
  let root = router.root_node()
  let (path1, found1) = find_case_insensitive_path(root, "/users/profile")
  assert_eq(found1, true)
  match path1 {
    Some(p) => assert_eq(p == "/Users/Profile", true)
    None => assert_eq(false, true)
  }
  let (path2, found2) = find_case_insensitive_path(root, "/POSTS/show")
  assert_eq(found2, true)
  match path2 {
    Some(p) => assert_eq(p == "/Posts/Show", true)
    None => assert_eq(false, true)
  }
  let (path3, found3) = find_case_insensitive_path(root, "/notfound/path")
  assert_eq(found3, false)
  assert_eq(path3 is None, true)
}

///|
async test "test not found handler" {
  async fn not_found_handler(
    _req : @http.Request,
    _body : &@io.Reader,
    conn : @http.ServerConnection,
  ) -> Unit {
    conn.send_response(404, "NotFound") |> ignore
    conn.end_response()
  }

  let router = Router::new()
  router.not_found = Some(not_found_handler)
  router.get("/exists", dummy_handler)
  let (handle, _, _) = router.lookup("GET", "/notexists")
  assert_eq(handle is None, true)
}

///|
async test "test method not allowed" {
  let router = Router::new()
  router.get("/api/users", dummy_handler)
  router.post("/api/users", dummy_handler)
  let (get_handle, _, _) = router.lookup("GET", "/api/users")
  assert_eq(get_handle is Some(_), true)
  let (put_handle, _, _) = router.lookup("PUT", "/api/users")
  assert_eq(put_handle is None, true)
  let allow = router.allowed_methods("/api/users", "PUT")
  assert_eq(allow.contains("GET"), true)
  assert_eq(allow.contains("POST"), true)
}

///|
async test "test options handling" {
  let router = Router::new()
  router.get("/api/users", dummy_handler)
  router.post("/api/users", dummy_handler)
  router.put("/api/users", dummy_handler)
  let allow = router.allowed_methods("/api/users", "OPTIONS")
  assert_eq(allow.contains("GET"), true)
  assert_eq(allow.contains("POST"), true)
  assert_eq(allow.contains("PUT"), true)
  let (options_handle, _, _) = router.lookup("OPTIONS", "/api/users")
  assert_eq(options_handle is None, true)
}

///|
async test "test empty path and root path" {
  let router = Router::new()
  router.get("/", dummy_handler)
  let (handle1, _, _) = router.lookup("GET", "/")
  assert_eq(handle1 is Some(_), true)
  let (handle2, _, _) = router.lookup("GET", "")
  assert_eq(handle2 is None, true)
}

///|
async test "test multiple params" {
  let router = Router::new()
  router.get("/posts/:category/:id", dummy_handler)
  let (_, params, _) = router.lookup("GET", "/posts/tech/123")
  assert_eq(params.length(), 2)
  assert_eq(by_name(params, "category"), "tech")
  assert_eq(by_name(params, "id"), "123")
}

///|
async test "test catch-all with multiple segments" {
  let router = Router::new()
  router.get("/static/*filepath", dummy_handler)
  let (_, params, _) = router.lookup("GET", "/static/css/framework/style.css")
  assert_eq(params.length(), 1)
  assert_eq(by_name(params, "filepath"), "css/framework/style.css")
}

///|
async test "test param with catch-all conflict" {
  let router = Router::new()
  router.get("/api/:version/users", dummy_handler)
  router.get("/api/*rest", dummy_handler)
  let (handle1, params1, _) = router.lookup("GET", "/api/v1/users")
  assert_eq(handle1 is Some(_), true)
  assert_eq(by_name(params1, "version"), "v1")
  let (handle2, params2, _) = router.lookup("GET", "/api/v1/users/profile")
  assert_eq(handle2 is Some(_), true)
  assert_eq(by_name(params2, "rest"), "v1/users/profile")
}

///|
async test "test trailing slash redirect with existing route" {
  let router = Router::new()
  router.get("/users", dummy_handler)
  router.get("/posts/", dummy_handler)
  let (path1, code1) = router.try_redirect("GET", "/users/")
  assert_eq(path1 is Some(_), true)
  assert_eq(code1, 301)
  let (path2, code2) = router.try_redirect("GET", "/posts")
  assert_eq(path2 is Some(_), true)
  assert_eq(code2, 301)
}

///|
async test "test path fix disabled" {
  let router = Router::new()
  router.get("/Users", dummy_handler)
  let root = router.root_node()
  let (path, found) = find_case_insensitive_path(root, "/users")
  assert_eq(found, true)
  match path {
    Some(p) => assert_eq(p == "/Users", true)
    None => assert_eq(false, true)
  }
}

///|
async test "test catch-all at root" {
  let router = Router::new()
  router.get("/*path", dummy_handler)
  let (handle, params, _) = router.lookup("GET", "/any/path/here")
  assert_eq(handle is Some(_), true)
  assert_eq(by_name(params, "path"), "any/path/here")
}

///|
async test "test static route priority" {
  let router = Router::new()
  router.get("/users/:id", dummy_handler)
  router.get("/users/me", dummy_handler)
  let (handle1, params1, _) = router.lookup("GET", "/users/me")
  assert_eq(handle1 is Some(_), true)
  assert_eq(params1.length(), 0)
  let (handle2, params2, _) = router.lookup("GET", "/users/123")
  assert_eq(handle2 is Some(_), true)
  assert_eq(params2.length(), 1)
  assert_eq(by_name(params2, "id"), "123")
}
