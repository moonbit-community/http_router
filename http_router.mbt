///|
pub(all) struct Param {
  key : String
  value : String
}

///|
pub type Params = Array[Param]

// Explicit reference to moonbitlang/async package to avoid unused warning
// The package is used for async function types and async test support

///|
fn _ensure_async_package_imported() -> Int64 {
  @async.now()
}

///|
pub fn by_name(params : Params, name : String) -> String {
  for p in params {
    if p.key == name {
      return p.value
    }
  }
  ""
}

///|
pub type HttpHandle = async (@http.Request, &@io.Reader, @http.ServerConnection) -> Unit

///|
pub type Handle = async (
  @http.Request,
  &@io.Reader,
  @http.ServerConnection,
  Params,
) -> Unit

///|
priv enum SegmentKind {
  Static
  Param
  CatchAll
}

///|
struct Node {
  kind : SegmentKind
  name : String
  static_children : Array[Node]
  param_child : Node?
  catch_all_child : Node?
  handle : Handle?
}

///|
fn make_node(kind : SegmentKind, name : String) -> Node {
  {
    kind,
    name,
    static_children: [],
    param_child: None,
    catch_all_child: None,
    handle: None,
  }
}

///|
pub type PanicHandler = async (
  @http.Request,
  &@io.Reader,
  @http.ServerConnection,
  String,
) -> Unit

///|
pub(all) struct Router {
  mut get_root : Node?
  mut head_root : Node?
  mut post_root : Node?
  mut put_root : Node?
  mut delete_root : Node?
  mut patch_root : Node?
  mut options_root : Node?
  redirect_trailing_slash : Bool
  redirect_fixed_path : Bool
  handle_method_not_allowed : Bool
  handle_options : Bool
  mut not_found : HttpHandle?
  mut method_not_allowed : HttpHandle?
  mut global_options : HttpHandle?
  mut panic_handler : PanicHandler?
}

///|
pub fn Router::new() -> Router {
  {
    get_root: None,
    head_root: None,
    post_root: None,
    put_root: None,
    delete_root: None,
    patch_root: None,
    options_root: None,
    redirect_trailing_slash: true,
    redirect_fixed_path: true,
    handle_method_not_allowed: true,
    handle_options: true,
    not_found: None,
    method_not_allowed: None,
    global_options: None,
    panic_handler: None,
  }
}

///|
fn strings_equal_case_insensitive(s1 : String, s2 : String) -> Bool {
  if s1.length() != s2.length() {
    return false
  }
  for i in 0..<s1.length() {
    let c1 = s1.code_unit_at(i)
    let c2 = s2.code_unit_at(i)
    if c1 == c2 {
      continue
    }
    let c1_is_upper = c1 >= 'A' && c1 <= 'Z'
    let c1_is_lower = c1 >= 'a' && c1 <= 'z'
    let c2_is_upper = c2 >= 'A' && c2 <= 'Z'
    let c2_is_lower = c2 >= 'a' && c2 <= 'z'
    if (c1_is_upper && c2_is_lower) || (c1_is_lower && c2_is_upper) {
      let diff = if c1 > c2 { c1 - c2 } else { c2 - c1 }
      if diff != 32 {
        return false
      }
    } else {
      return false
    }
  }
  true
}

///|
fn split_path(path : String) -> Array[String] {
  let segments : Array[String] = []
  if path == "" || path == "/" {
    return segments
  }
  let mut rest = path
  if rest.has_prefix("/") {
    rest = rest[1:].to_string()
  }
  while true {
    match rest.find("/") {
      Some(i) => {
        if i > 0 {
          segments.push(rest[:i].to_string())
        }
        rest = rest[i + 1:].to_string()
      }
      None => {
        if rest != "" {
          segments.push(rest)
        }
        break
      }
    }
  }
  segments
}

///|
fn insert_route(
  node : Node,
  segments : Array[String],
  idx : Int,
  path : String,
  handle : Handle,
) -> Node raise {
  if idx == segments.length() {
    guard node.handle is None else {
      abort("router: duplicate route for path \{path}")
    }
    return {
      kind: node.kind,
      name: node.name,
      static_children: node.static_children,
      param_child: node.param_child,
      catch_all_child: node.catch_all_child,
      handle: Some(handle),
    }
  }
  let seg = segments[idx]
  let is_last = idx == segments.length() - 1
  let (kind, name) = if seg.has_prefix(":") {
    (Param, seg[1:].to_string())
  } else if seg.has_prefix("*") {
    guard is_last else {
      abort("router: catch-all must be the final segment: \{path}")
    }
    (CatchAll, seg[1:].to_string())
  } else {
    (Static, seg)
  }
  match kind {
    Static => {
      let mut child_index = -1
      for j in 0..<node.static_children.length() {
        if node.static_children[j].name == name {
          child_index = j
          break
        }
      }
      let updated_child = if child_index == -1 {
        let child = make_node(Static, name)
        insert_route(child, segments, idx + 1, path, handle)
      } else {
        let child = node.static_children[child_index]
        insert_route(child, segments, idx + 1, path, handle)
      }
      let new_static_children : Array[Node] = []
      if child_index == -1 {
        for j in 0..<node.static_children.length() {
          new_static_children.push(node.static_children[j])
        }
        new_static_children.push(updated_child)
      } else {
        for j in 0..<node.static_children.length() {
          if j == child_index {
            new_static_children.push(updated_child)
          } else {
            new_static_children.push(node.static_children[j])
          }
        }
      }
      {
        kind: node.kind,
        name: node.name,
        static_children: new_static_children,
        param_child: node.param_child,
        catch_all_child: node.catch_all_child,
        handle: node.handle,
      }
    }
    Param => {
      let updated_child = match node.param_child {
        Some(param_node) => {
          guard param_node.name == name else {
            abort(
              "router: conflicting parameter name: \{param_node.name} vs \{name}",
            )
          }
          insert_route(param_node, segments, idx + 1, path, handle)
        }
        None => {
          let child = make_node(Param, name)
          insert_route(child, segments, idx + 1, path, handle)
        }
      }
      {
        kind: node.kind,
        name: node.name,
        static_children: node.static_children,
        param_child: Some(updated_child),
        catch_all_child: node.catch_all_child,
        handle: node.handle,
      }
    }
    CatchAll => {
      let updated_child = match node.catch_all_child {
        Some(catch_all_node) => {
          guard catch_all_node.name == name else {
            abort(
              "router: conflicting catch-all name: \{catch_all_node.name} vs \{name}",
            )
          }
          insert_route(catch_all_node, segments, idx + 1, path, handle)
        }
        None => {
          let child = make_node(CatchAll, name)
          insert_route(child, segments, idx + 1, path, handle)
        }
      }
      {
        kind: node.kind,
        name: node.name,
        static_children: node.static_children,
        param_child: node.param_child,
        catch_all_child: Some(updated_child),
        handle: node.handle,
      }
    }
  }
}

///|
fn add_route_to_root(
  root : Node?,
  path : String,
  handle : Handle,
) -> Node raise {
  let segments = split_path(path)
  let node = match root {
    Some(r) => r
    None => make_node(Static, "")
  }
  insert_route(node, segments, 0, path, handle)
}

///|
fn clone_params(params : Params) -> Params {
  let new_params : Params = []
  for p in params {
    new_params.push(p)
  }
  new_params
}

///|
fn lookup_from_node(
  node : Node,
  segments : Array[String],
  idx : Int,
  params : Params,
) -> (Handle?, Params, Bool) raise {
  if idx == segments.length() {
    match node.handle {
      Some(h) => (Some(h), params, false)
      None => (None, params, false)
    }
  } else {
    let seg = segments[idx]

    // 1. try static children (most specific)
    for child in node.static_children {
      if child.name == seg {
        let (h, p, found) = lookup_from_node(child, segments, idx + 1, params)
        if h is Some(_) || found {
          return (h, p, found)
        }
      }
    }

    // 2. try param child
    match node.param_child {
      Some(param_node) => {
        let new_params = clone_params(params)
        new_params.push({ key: param_node.name, value: seg })
        let (h, p, found) = lookup_from_node(
          param_node,
          segments,
          idx + 1,
          new_params,
        )
        if h is Some(_) || found {
          return (h, p, found)
        }
      }
      None => ignore(())
    }

    // 3. try catch-all child (captures the rest of the path)
    match node.catch_all_child {
      Some(catch_all_node) => {
        let tail_segments : Array[String] = []
        for j in idx..<segments.length() {
          tail_segments.push(segments[j])
        }
        let value = tail_segments.join("/")
        let new_params = clone_params(params)
        new_params.push({ key: catch_all_node.name, value })
        match catch_all_node.handle {
          Some(h) => (Some(h), new_params, false)
          None => (None, new_params, false)
        }
      }
      None => (None, params, false)
    }
  }
}

///|
fn lookup_in_root(root : Node?, path : String) -> (Handle?, Params, Bool) raise {
  // empty path should not match the root route (only "/" does)
  if path == "" {
    return (None, [], false)
  }
  match root {
    None => (None, [], false)
    Some(root) => {
      let segments = split_path(path)
      let params : Params = []
      if segments.is_empty() {
        match root.handle {
          Some(h) => (Some(h), params, false)
          None => (None, params, false)
        }
      } else {
        lookup_from_node(root, segments, 0, params)
      }
    }
  }
}

///|
fn Router::method_root(self : Router, method_name : String) -> Node? {
  match method_name {
    "GET" => self.get_root
    "HEAD" => self.head_root
    "POST" => self.post_root
    "PUT" => self.put_root
    "DELETE" => self.delete_root
    "PATCH" => self.patch_root
    "OPTIONS" => self.options_root
    _ => None
  }
}

///|
pub fn Router::root_node(self : Router) -> Node? {
  self.get_root
}

///|
fn Router::set_method_root(
  self : Router,
  method_name : String,
  root : Node,
) -> Unit {
  match method_name {
    "GET" => self.get_root = Some(root)
    "HEAD" => self.head_root = Some(root)
    "POST" => self.post_root = Some(root)
    "PUT" => self.put_root = Some(root)
    "DELETE" => self.delete_root = Some(root)
    "PATCH" => self.patch_root = Some(root)
    "OPTIONS" => self.options_root = Some(root)
    _ => abort("router: unsupported method \{method_name}")
  }
}

///|
pub fn Router::handle(
  self : Router,
  method_name : String,
  path : String,
  handle : Handle,
) -> Unit raise {
  guard path.has_prefix("/") else { abort("router: path must begin with '/'") }
  let old_root = self.method_root(method_name)
  let new_root = add_route_to_root(old_root, path, handle)
  self.set_method_root(method_name, new_root)
}

///|
pub fn Router::get(self : Router, path : String, handle : Handle) -> Unit raise {
  self.handle("GET", path, handle)
}

///|
pub fn Router::head(
  self : Router,
  path : String,
  handle : Handle,
) -> Unit raise {
  self.handle("HEAD", path, handle)
}

///|
pub fn Router::post(
  self : Router,
  path : String,
  handle : Handle,
) -> Unit raise {
  self.handle("POST", path, handle)
}

///|
pub fn Router::put(self : Router, path : String, handle : Handle) -> Unit raise {
  self.handle("PUT", path, handle)
}

///|
pub fn Router::delete(
  self : Router,
  path : String,
  handle : Handle,
) -> Unit raise {
  self.handle("DELETE", path, handle)
}

///|
pub fn Router::patch(
  self : Router,
  path : String,
  handle : Handle,
) -> Unit raise {
  self.handle("PATCH", path, handle)
}

///|
pub fn Router::options(
  self : Router,
  path : String,
  handle : Handle,
) -> Unit raise {
  self.handle("OPTIONS", path, handle)
}

///|
pub fn Router::lookup(
  self : Router,
  method_name : String,
  path : String,
) -> (Handle?, Params, Bool) raise {
  let (handle, params, found) = lookup_in_root(
    self.method_root(method_name),
    path,
  )
  if handle is Some(_) {
    (handle, params, found)
  } else if method_name == "HEAD" {
    lookup_in_root(self.get_root, path)
  } else {
    (None, params, found)
  }
}

///|
pub fn Router::allowed_methods(
  self : Router,
  path : String,
  req_method : String,
) -> String raise {
  if self.handle_options {
    let methods : Array[String] = []
    if lookup_in_root(self.get_root, path).0 is Some(_) {
      methods.push("GET")
    }
    if lookup_in_root(self.head_root, path).0 is Some(_) {
      methods.push("HEAD")
    }
    if lookup_in_root(self.post_root, path).0 is Some(_) {
      methods.push("POST")
    }
    if lookup_in_root(self.put_root, path).0 is Some(_) {
      methods.push("PUT")
    }
    if lookup_in_root(self.delete_root, path).0 is Some(_) {
      methods.push("DELETE")
    }
    if lookup_in_root(self.patch_root, path).0 is Some(_) {
      methods.push("PATCH")
    }
    // For an OPTIONS request, include OPTIONS itself when other methods exist
    if req_method == "OPTIONS" && !methods.is_empty() {
      methods.push("OPTIONS")
    }
    if methods.is_empty() {
      ""
    } else {
      methods.join(", ")
    }
  } else {
    ""
  }
}

///|
pub fn find_case_insensitive_path(
  root : Node?,
  path : String,
) -> (String?, Bool) {
  match root {
    None => (None, false)
    Some(root) => {
      let segments = split_path(path)
      if segments.is_empty() {
        match root.handle {
          Some(_) => (Some("/"), true)
          None => (None, false)
        }
      } else {
        let mut node = root
        let fixed_segments : Array[String] = []
        for i in 0..<segments.length() {
          let seg = segments[i]
          let mut matched = false
          // try exact match first
          for child in node.static_children {
            if child.name == seg {
              fixed_segments.push(seg)
              node = child
              matched = true
              break
            }
          }
          if !matched {
            // try case-insensitive match for static children
            for child in node.static_children {
              if strings_equal_case_insensitive(child.name, seg) {
                fixed_segments.push(child.name)
                node = child
                matched = true
                break
              }
            }
          }
          if !matched {
            // try param child
            match node.param_child {
              Some(param_node) => {
                fixed_segments.push(seg)
                node = param_node
                matched = true
              }
              None => ignore(())
            }
          }
          if !matched {
            // try catch-all child
            match node.catch_all_child {
              Some(catch_all_node) => {
                fixed_segments.push(seg)
                node = catch_all_node
                matched = true
              }
              None => ignore(())
            }
          }
          if !matched {
            return (None, false)
          }
        }
        match node.handle {
          Some(_) => {
            let fixed_path = "/" + fixed_segments.join("/")
            let needs_trailing_slash = path.has_suffix("/")
            let fixed_path_with_slash = if needs_trailing_slash &&
              !fixed_path.has_suffix("/") {
              fixed_path + "/"
            } else {
              fixed_path
            }
            if fixed_path_with_slash != path {
              (Some(fixed_path_with_slash), true)
            } else {
              (Some(fixed_path_with_slash), false)
            }
          }
          None => (None, false)
        }
      }
    }
  }
}

///|
pub fn Router::try_redirect(
  self : Router,
  method_str : String,
  path : String,
) -> (String?, Int) raise {
  if self.redirect_trailing_slash {
    let path_has_slash = path.has_suffix("/")
    let path_without_slash = if path_has_slash && path != "/" {
      path[:path.length() - 1].to_string()
    } else {
      ""
    }
    let path_with_slash = if !path_has_slash { path + "/" } else { "" }
    if path_without_slash != "" {
      let (handle, _, _) = self.lookup(method_str, path_without_slash)
      if handle is Some(_) {
        return (Some(path_without_slash), 301)
      }
    }
    if path_with_slash != "" {
      let (handle, _, _) = self.lookup(method_str, path_with_slash)
      if handle is Some(_) {
        return (Some(path_with_slash), 301)
      }
    }
  }
  if self.redirect_fixed_path {
    let root = self.method_root(method_str)
    let (fixed_path, found) = find_case_insensitive_path(root, path)
    if found && fixed_path is Some(fp) && fp != path {
      return (fixed_path, 301)
    }
  }
  (None, 0)
}

///|
pub async fn Router::serve_http(
  self : Router,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let method_str = match request.meth {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Options => "OPTIONS"
    Patch => "PATCH"
    _ => ""
  }
  let (handle, params, _) = self.lookup(method_str, request.path)
  match handle {
    Some(h) =>
      match self.panic_handler {
        Some(ph) => {
          let result = try {
            h(request, body, conn, params)
            None
          } catch {
            e => Some(e.to_string())
          }
          match result {
            Some(error_msg) => ph(request, body, conn, error_msg)
            None => ignore(())
          }
        }
        None => h(request, body, conn, params)
      }
    None => {
      // try redirect
      let (redirect_path, redirect_code) = self.try_redirect(
        method_str,
        request.path,
      )
      match redirect_path {
        Some(redir) => {
          conn.send_response(redirect_code, "Moved Permanently", extra_headers={
            "Location": redir,
          })
          |> ignore
          conn.end_response()
          return
        }
        None => ignore(())
      }
      if request.meth is Options && self.handle_options {
        match self.global_options {
          Some(opt_handler) => opt_handler(request, body, conn)
          None => {
            let allow = self.allowed_methods(request.path, method_str)
            if allow != "" {
              conn.send_response(200, "OK", extra_headers={ "Allow": allow })
              |> ignore
              conn.end_response()
            } else {
              match self.not_found {
                Some(nf) => nf(request, body, conn)
                None => {
                  conn.send_response(404, "NotFound") |> ignore
                  conn.end_response()
                }
              }
            }
          }
        }
      } else if self.handle_method_not_allowed {
        let allow = self.allowed_methods(request.path, method_str)
        if allow != "" {
          match self.method_not_allowed {
            Some(ma) => ma(request, body, conn)
            None => {
              conn.send_response(405, "MethodNotAllowed", extra_headers={
                "Allow": allow,
              })
              |> ignore
              conn.end_response()
            }
          }
        } else {
          match self.not_found {
            Some(nf) => nf(request, body, conn)
            None => {
              conn.send_response(404, "NotFound") |> ignore
              conn.end_response()
            }
          }
        }
      } else {
        match self.not_found {
          Some(nf) => nf(request, body, conn)
          None => {
            conn.send_response(404, "NotFound") |> ignore
            conn.end_response()
          }
        }
      }
    }
  }
}
