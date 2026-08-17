# ─────────────────────────────────────────────────────────────────────────────
# Access control.
#
# The deployment splits into two roles: the team may read, one person may
# upload. These tests pin the boundary, including the cases that would quietly
# open the API up — an unset variable meaning "open", or a viewer password
# being accepted on a write endpoint.
#
# auth.R reads its configuration once at source() time, so each scenario is
# exercised by re-sourcing it under different environment variables.
# ─────────────────────────────────────────────────────────────────────────────

with_auth_env <- function(viewer = "", admin = "", code) {
  old <- Sys.getenv(c("ILIFT_VIEWER_PASSWORD", "ILIFT_ADMIN_TOKEN"), unset = NA)
  on.exit({
    for (n in names(old)) {
      if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, setNames(list(old[[n]]), n))
    }
    source(file.path(backend_dir, "R", "auth.R"))   # restore ambient config
  }, add = TRUE)

  Sys.setenv(ILIFT_VIEWER_PASSWORD = viewer, ILIFT_ADMIN_TOKEN = admin)
  source(file.path(backend_dir, "R", "auth.R"))
  force(code)
}

req_with <- function(token = NULL, path = "/api/metrics", method = "GET") {
  r <- list(PATH_INFO = path, REQUEST_METHOD = method, argsQuery = list())
  if (!is.null(token)) r$HTTP_AUTHORIZATION <- paste("Bearer", token)
  r
}

test_that("with nothing configured the API is open", {
  with_auth_env(viewer = "", admin = "", {
    expect_equal(auth_level(req_with()), "admin")
    expect_equal(auth_level(req_with(path = "/api/upload")), "admin")
  })
})

test_that("viewer password gates reads", {
  with_auth_env(viewer = "team-secret", admin = "admin-secret-token-xyz", {
    expect_equal(auth_level(req_with()), "anonymous")
    expect_equal(auth_level(req_with("wrong")), "anonymous")
    expect_equal(auth_level(req_with("team-secret")), "viewer")
  })
})

test_that("admin token is recognised and outranks the viewer password", {
  with_auth_env(viewer = "team-secret", admin = "admin-secret-token-xyz", {
    expect_equal(auth_level(req_with("admin-secret-token-xyz")), "admin")
  })
})

test_that("a viewer cannot reach write endpoints", {
  with_auth_env(viewer = "team-secret", admin = "admin-secret-token-xyz", {
    # This is the whole point of the split: reading is fine, writing is not.
    expect_equal(auth_level(req_with("team-secret", "/api/upload")), "viewer")
    expect_true(is_write_path("/api/upload"))
    expect_true(is_write_path("/api/refresh"))
    expect_true(is_write_path("/api/upload?slot=ris"))
    expect_false(is_write_path("/api/metrics"))
    expect_false(is_write_path("/api/meta"))
  })
})

test_that("protecting writes alone still leaves reads open", {
  with_auth_env(viewer = "", admin = "admin-secret-token-xyz", {
    expect_equal(auth_level(req_with()), "viewer")          # anyone may read
    expect_equal(auth_level(req_with("admin-secret-token-xyz")), "admin")
  })
})

test_that("credentials are accepted from header, alt header, or query", {
  with_auth_env(viewer = "team-secret", admin = "admin-secret-token-xyz", {
    expect_equal(auth_level(req_with("team-secret")), "viewer")

    alt <- list(PATH_INFO = "/api/metrics", REQUEST_METHOD = "GET",
                argsQuery = list(), HTTP_X_ILIFT_TOKEN = "team-secret")
    expect_equal(auth_level(alt), "viewer")

    q <- list(PATH_INFO = "/api/metrics", REQUEST_METHOD = "GET",
              argsQuery = list(token = "team-secret"))
    expect_equal(auth_level(q), "viewer")
  })
})

test_that("secure_equals behaves like == but without early exit", {
  expect_true(secure_equals("abc", "abc"))
  expect_false(secure_equals("abc", "abd"))
  expect_false(secure_equals("abc", "ab"))     # length mismatch
  expect_false(secure_equals("abc", ""))
  expect_true(secure_equals("", ""))
  expect_false(secure_equals(NULL, "x"))
  expect_true(secure_equals(NULL, NULL))
})

test_that("a near-miss token is rejected", {
  with_auth_env(viewer = "team-secret", admin = "admin-secret-token-xyz", {
    expect_equal(auth_level(req_with("admin-secret-token-xy")),   "anonymous") # truncated
    expect_equal(auth_level(req_with("admin-secret-token-xyzz")), "anonymous") # extended
    expect_equal(auth_level(req_with("Admin-Secret-Token-XYZ")),  "anonymous") # wrong case
    expect_equal(auth_level(req_with("admin-secret-token-xyz ")), "anonymous") # trailing space
  })
})

test_that("extra whitespace after 'Bearer' is tolerated, per RFC 6750", {
  with_auth_env(viewer = "team-secret", admin = "admin-secret-token-xyz", {
    r <- list(PATH_INFO = "/api/metrics", REQUEST_METHOD = "GET", argsQuery = list(),
              HTTP_AUTHORIZATION = "Bearer   admin-secret-token-xyz")
    expect_equal(auth_level(r), "admin")
  })
})

test_that("whitespace inside a query-param token is not stripped", {
  # No 'Bearer' prefix to absorb it here, so this really is a different secret.
  with_auth_env(viewer = "team-secret", admin = "admin-secret-token-xyz", {
    q <- list(PATH_INFO = "/api/metrics", REQUEST_METHOD = "GET",
              argsQuery = list(token = " team-secret"))
    expect_equal(auth_level(q), "anonymous")
  })
})

test_that("auth_status reports the configured mode", {
  with_auth_env(viewer = "p", admin = "t", {
    s <- auth_status()
    expect_true(s$read_protected)
    expect_true(s$write_protected)
    expect_equal(s$mode, "viewer+admin")
  })
  with_auth_env(viewer = "", admin = "", {
    expect_equal(auth_status()$mode, "open")
  })
})
