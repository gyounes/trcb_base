-define(APP, trcb_base).
-define(METRICS_DEFAULT, true).

-define(PEER_SERVICE, partisan_peer_service).
-define(PEER_SERVICE_MANAGER, partisan_default_peer_service_manager).
-define(TCSB, trcb_base_tcsb).
-define(RESENDER, trcb_base_resender).
-define(FIRST_TCBCAST_TAG, first).
-define(RESEND_TCBCAST_TAG, first).
-define(WAIT_TIME_BEFORE_CHECK_RESEND, 5000).
-define(WAIT_TIME_BEFORE_RESEND, 10000).

-type actor() :: term().
-type message() :: term().
-type timestamp() :: vclock:vclock().
-type vclock() :: vclock:vclock().
-type timestamp_matrix() :: mclock:mclock().
