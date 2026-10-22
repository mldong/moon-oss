///|
test "symlink headers carry the target and optional switches" {
  assert_eq(symlink_headers("target/key.txt"), [
    ("x-oss-symlink-target", "target/key.txt"),
  ])
  assert_eq(
    symlink_headers(
      "target/key.txt",
      forbid_overwrite=true,
      storage_class="IA",
      acl="private",
    ),
    [
      ("x-oss-symlink-target", "target/key.txt"),
      ("x-oss-forbid-overwrite", "true"),
      ("x-oss-storage-class", "IA"),
      ("x-oss-object-acl", "private"),
    ],
  )
}
