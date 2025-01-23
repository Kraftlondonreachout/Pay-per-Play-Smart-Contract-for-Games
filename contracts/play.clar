;; Pay-per-Play Smart Contract for Games

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLAY-PRICE u1000000) ;; 1 STX
(define-constant DEVELOPER-SHARE u80) ;; 80%
(define-constant COMMUNITY-SHARE u20) ;; 20%

;; data vars
(define-data-var developer-address principal CONTRACT-OWNER)

;; data maps
(define-map player-sessions principal uint)
(define-map revenue-stats { game: principal } { total-plays: uint, total-revenue: uint })

;; public functions
(define-public (start-game-session)
    (let
        (
            (current-sessions (default-to u0 (map-get? player-sessions tx-sender)))
        )
        (try! (stx-transfer? PLAY-PRICE tx-sender (var-get developer-address)))
        (map-set player-sessions tx-sender (+ current-sessions u1))
        (ok true)
    )
)

;; read only functions
(define-read-only (get-player-sessions (player principal))
    (ok (default-to u0 (map-get? player-sessions player)))
)

(define-read-only (get-play-price)
    (ok PLAY-PRICE)
)

;; admin functions
(define-public (set-developer-address (new-address principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) (err true))
        (ok (var-set developer-address new-address))
    )
)
