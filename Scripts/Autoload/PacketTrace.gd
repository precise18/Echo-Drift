extends Node
## TEMP DEBUG: shared packet-instrumentation helper for the networking-layer
## audit (see PACKET_TRACE.md). Grep "PacketTrace" or "[PACKET-TRACE]" to
## find/remove every call site added for this pass.
##
## Two call shapes, matching what's actually knowable at each end:
##  - sent(): logged at the call site right before/after handing the
##    packet to the transport. There is no "actual handler" yet — whether
##    it's ever handled is only knowable from the receiving side's own log
##    line (which may be on a different machine's console entirely for a
##    real network peer; both peers' logs have to be compared by hand).
##  - received(): logged from inside the handler itself, so it can report
##    whether the packet was actually acted on (`actual_handler`) or fell
##    through a guard clause and was ignored.

func sent(packet_type: String, sender, receiver, payload: String, expected_handler: String) -> void:
	print("[PACKET-TRACE][%d] SENT     type=%s sender=%s receiver=%s payload=%s expected_handler=%s" % [
		Time.get_ticks_msec(), packet_type, str(sender), str(receiver), payload, expected_handler
	])

func received(packet_type: String, sender, receiver, payload: String, expected_handler: String, actual_handler: String) -> void:
	print("[PACKET-TRACE][%d] RECEIVED type=%s sender=%s receiver=%s payload=%s expected_handler=%s actual_handler=%s" % [
		Time.get_ticks_msec(), packet_type, str(sender), str(receiver), payload, expected_handler, actual_handler
	])
