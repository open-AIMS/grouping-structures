# A library in the repository root goes first when it exists, so that a run here
# uses the bayesnec this study pins rather than whatever the account happens to
# have installed. Prepended only when present: a stale lib/ that shadows the
# intended library silently is the trap recorded in the negative-response-
# conventions compendium, and an absent one must not become an error.
local({
  lib <- file.path(getwd(), "lib")
  if (dir.exists(lib)) .libPaths(c(lib, .libPaths()))
})
