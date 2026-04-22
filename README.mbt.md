## http_router (MoonBit High-Performance HTTP Router)

A high-performance HTTP router implemented in MoonBit, built on top of the `moonbitlang/async` library and inspired by the widely used Go project [`julienschmidt/httprouter`](https://github.com/julienschmidt/httprouter).  
It provides fast and predictable route matching suitable for building web services, APIs and gateways in MoonBit.

This project can be used as:
- **A learning example** for MoonBit async programming and HTTP ecosystem.
- **A routing layer** inside custom HTTP servers / gateways.
- **A comparison target** against Go `httprouter` in terms of design and performance.

---

## Features

- **High-performance routing**
  - Uses a **radix tree** (compressed prefix tree) as the internal routing structure.
  - Benchmarks are provided for large sets of static and mixed routes.
- **Rich routing syntax**
  - **Static routes**: `/users/profile`
  - **Parameter routes**: `/user/:id`
  - **Catch-all routes**: `/static/*filepath`
- **Multiple HTTP methods**
  - `GET`, `HEAD`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`
- **Route parameters**
  - Parameters are stored in `Params`.
  - Helper `by_name(params, "id")` to access parameters by name.
- **Behavior aligned with Go `httprouter`**
  - Trailing-slash redirects (`/users` ↔ `/users/`)
  - Case-insensitive path fixing (`/Users/Profile` ↔ `/users/profile`)
  - 404 / 405 / OPTIONS handling
  - HEAD automatically falls back to the GET handler
  - Panic recovery via a customizable `PanicHandler`
- **Async HTTP integration**
  - Uses `moonbitlang/async`.
  - Exposes `Router::serve_http` for direct integration with an HTTP server.

---

## Environment & Dependencies

- **Language**: MoonBit
- **Core dependency**:
  - `moonbitlang/async` (async support, timing, async tests/benchmarks)
- Dependencies are declared in:
  - `moon.mod.json`
  - `moon.pkg.json`

Make sure the MoonBit toolchain is installed and available in your environment, then run commands from the project root.

---

## Getting Started

### 1. Clone the repository

```bash
git clone <your-repo-url> http_router
cd http_router
```

### 2. Build & check

```bash
moon check   # type and lint check
moon info    # generate / update package interfaces
moon fmt     # format the code
```

### 3. Run tests & benchmarks

There are comprehensive functional tests and simple benchmarks in `http_router_test.mbt`:

```bash
moon test
```

If you changed observable behavior and need to update snapshots:

```bash
moon test --update
```

---

## Basic Usage

The following example shows how to create a `Router`, register routes and plug it into an HTTP server (pseudo-code, focused on router usage):

```moonbit nocheck
let router = Router::new()

// Static route
router.get("/hello", async fn(req, body, conn, _params) -> Unit {
  conn.send_response(200, "OK", extra_headers={}) |> ignore
  conn.end_response()
})

// Route with path parameter
router.get("/user/:id", async fn(req, body, conn, params) -> Unit {
  let user_id = by_name(params, "id")
  // handle user_id ...
  conn.send_response(200, "OK") |> ignore
  conn.end_response()
})

// Catch-all route
router.get("/static/*filepath", async fn(req, body, conn, params) -> Unit {
  let path = by_name(params, "filepath")
  // serve static file at path ...
  conn.send_response(200, "OK") |> ignore
  conn.end_response()
})

// Inside your HTTP server:
// for each incoming request:
//   router.serve_http(request, &body, conn)
```

More available APIs:
- `router.post(path, handle)`
- `router.put(path, handle)`
- `router.delete(path, handle)`
- `router.patch(path, handle)`
- `router.options(path, handle)`
- `router.lookup(method, path)` for pure route lookup (without sending responses)

---

## Design Overview

- **Routing tree**
  - Internal nodes (`Node`) are classified as:
    - Static segments
    - Parameter segments (`:param`)
    - Catch-all segments (`*name`)
  - Route registration checks for conflicting parameter names and invalid catch-all positions and aborts early with a clear message.
- **Lookup process**
  - Always prefers static segments.
  - Falls back to parameter segments if static match fails.
  - Finally tries catch-all segments when present.
  - Supports automatic HEAD → GET fallback when no explicit HEAD handler is registered.
- **Error and edge handling**
  - When no route is found, behavior depends on configuration:
    - Optional redirect (trailing slash / case-insensitive)
    - 404 / 405 responses
    - OPTIONS responses with `Allow` header

For full implementation details, see `http_router.mbt` and tests in `http_router_test.mbt`.

---

## Performance & Comparison

This repository includes benchmarks for:
- Simple routes
- Large numbers of static routes (e.g. bulk-registered `/static/data/:id`)
- Multi-parameter routes
- Catch-all heavy and mixed workloads

The **goal** is to achieve **throughput comparable to Go `httprouter` for similar route sets**.  
For a detailed comparison you can:
- Run `moon test` in this project and observe printed RPS-like numbers.
- Run the official benchmarks in the Go `httprouter` repository on the same machine.

---

## Extending & Integrating

To adapt this router to your own project, you can:
- Wrap it with higher-level APIs (middlewares, route groups, etc.).
- Add additional HTTP methods or custom method names if needed.
- Integrate it with your own MoonBit HTTP server implementation in a single package.

---

## License

This project is released under an open source license compatible with the upstream project.  
See the `LICENSE` file for full details.

