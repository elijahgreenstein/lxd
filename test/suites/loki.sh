test_loki() {
  local log_file="${TEST_DIR}/loki.logs"
  spawn_loki

  lxc config set loki.api.url="http://127.0.0.1:3100" loki.auth.username="loki" loki.auth.password="pass"
  lxc config set loki.labels="env=prod,app=web" loki.types="lifecycle,logging,ovn"

  ensure_import_testimage
  lxc launch testimage c1
  lxc restart -f c1
  lxc delete -f c1

  lxc init --empty c2
  lxc delete c2

  # Changing the loki configuration sends any accumulated logs to the test server
  lxc config set loki.api.url="" loki.auth.username="" loki.auth.password="" loki.labels="" loki.types=""

  # Check there are both logging and lifecycle entries
  jq --exit-status '.streams[].stream | select(.type == "logging")' "${log_file}"
  jq --exit-status '.streams[].stream | select(.type == "lifecycle")' "${log_file}"

  # Check the expected lifecycle events for c1
  jq --exit-status '.streams[] | select(.stream.name == "c1") | .values[][1]' "${log_file}"  # debug
  jq --exit-status '.streams[] | select(.stream.name == "c1") | .values[][1] | select(contains("action=\"instance-created\""))' "${log_file}"
  jq --exit-status '.streams[] | select(.stream.name == "c1") | .values[][1] | select(contains("action=\"instance-started\""))' "${log_file}"
  jq --exit-status '.streams[] | select(.stream.name == "c1") | .values[][1] | select(contains("action=\"instance-restarted\""))' "${log_file}"
  jq --exit-status '.streams[] | select(.stream.name == "c1") | .values[][1] | select(contains("action=\"instance-stopped\""))' "${log_file}"
  jq --exit-status '.streams[] | select(.stream.name == "c1") | .values[][1] | select(contains("action=\"instance-deleted\""))' "${log_file}"

  # Check the expected lifecycle events for c2
  jq --exit-status '.streams[] | select(.stream.name == "c2") | .values[][1]' "${log_file}"  # debug
  jq --exit-status '.streams[] | select(.stream.name == "c2") | .values[][1] | select(contains("action=\"instance-created\""))' "${log_file}"
  jq --exit-status '.streams[] | select(.stream.name == "c2") | .values[][1] | select(contains("action=\"instance-deleted\""))' "${log_file}"

  # Cleanup
  kill_loki
  rm "${log_file}"
}

test_loki_security_types() {
  local log_file="${TEST_DIR}/loki.logs"
  spawn_loki

  sub_test "Verify security is accepted as a valid loki.types value"
  lxc config set loki.api.url="http://127.0.0.1:3100" loki.auth.username="loki" loki.auth.password="pass"
  lxc config set loki.types="lifecycle,logging,security"
  [ "$(lxc config get loki.types)" = "lifecycle,logging,security" ]

  # An unknown event type must be rejected by the validator.
  ! lxc config set loki.types="lifecycle,logging,invalid_type" || false

  sub_test "Verify lifecycle events still route to Loki when security is included in loki.types"
  ensure_import_testimage
  lxc launch testimage c-loki-security
  lxc delete -f c-loki-security

  # Changing the loki configuration sends any accumulated logs to the test server.
  lxc config set loki.api.url="" loki.auth.username="" loki.auth.password="" loki.types=""

  jq --exit-status '.streams[].stream | select(.type == "lifecycle")' "${log_file}"

  # Cleanup.
  kill_loki
  rm "${log_file}"
}

test_loki_security_forwarding() {
  local log_file="${TEST_DIR}/loki.logs"
  spawn_loki

  sub_test "Verify security events forward to Loki with OWASP serialization"
  lxc config set loki.api.url="http://127.0.0.1:3100" loki.auth.username="loki" loki.auth.password="pass"
  lxc config set loki.types="security"

  # Trigger authn_login_fail:tls by presenting an untrusted client cert to an
  # authenticated endpoint (mirrors test_authn_events in security.sh).
  gen_cert_and_key "loki-untrusted-cert"
  curl --insecure --silent \
    --cert "${LXD_CONF}/loki-untrusted-cert.crt" \
    --key "${LXD_CONF}/loki-untrusted-cert.key" \
    "https://${LXD_ADDR}/1.0/instances" \
    | jq --exit-status '.error_code == 403'

  # Changing the loki configuration sends any accumulated logs to the test server.
  lxc config set loki.api.url="" loki.auth.username="" loki.auth.password="" loki.types=""

  # The security stream must exist and every line must carry OWASP fields.
  jq --exit-status '.streams[].stream | select(.type == "security")' "${log_file}"
  # Assert OWASP fields that securityEventToOWASP populates unconditionally.
  # user_id, useragent and source_ip are only set when the requestor has the
  # corresponding metadata, which is not the case for authn_login_fail:tls.
  jq --exit-status 'all(
    .streams[] | select(.stream.type == "security") | .values[][1];
    fromjson | (.appid == "lxd" and .type == "security" and (.event | startswith("authn_login_fail")) and has("cluster_identifier") and has("datetime") and has("event_source"))
  )' "${log_file}"

  # mini-loki holds loki.logs open for the process lifetime, so a plain rm
  # leaves the daemon writing to an unlinked inode. Restart it to get a fresh
  # file at the same path for the second sub-test.
  kill_loki
  rm "${log_file}"
  spawn_loki

  sub_test "Verify security events are filtered when not in loki.types"
  lxc config set loki.api.url="http://127.0.0.1:3100" loki.auth.username="loki" loki.auth.password="pass"
  lxc config set loki.types="lifecycle"

  ensure_import_testimage
  lxc launch testimage c-no-security-events
  lxc delete -f c-no-security-events

  # Flush logs.
  lxc config set loki.api.url="" loki.auth.username="" loki.auth.password="" loki.types=""

  # Lifecycle events must be present (proves forwarding is alive); security
  # events must be absent (proves the type filter works).
  jq --exit-status '.streams[].stream | select(.type == "lifecycle")' "${log_file}"
  ! jq --exit-status '.streams[].stream | select(.type == "security")' "${log_file}" || false

  # Cleanup.
  kill_loki
  rm "${log_file}"
}
