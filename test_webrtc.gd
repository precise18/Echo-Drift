extends SceneTree
func _init():
    var webrtc_conn = WebRTCPeerConnection.new()
    var err = webrtc_conn.initialize({
        "iceServers": [
            { "urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] },
            { "urls": ["turn:openrelay.metered.ca:80", "turn:openrelay.metered.ca:443", "turn:openrelay.metered.ca:443?transport=tcp"], "username": "openrelayproject", "credential": "openrelayproject" }
        ]
    })
    print("Initialize error code: ", err)
    quit()
