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



;; Add to data vars
(define-data-var refund-window uint u3600) ;; 1 hour in seconds
(define-map last-play-timestamp principal uint)

;; Add new function
(define-public (request-refund)
    (let 
        (
            (last-timestamp (default-to u0 (map-get? last-play-timestamp tx-sender)))
            (current-time stacks-block-height)
        )
        (asserts! (< (- current-time last-timestamp) (var-get refund-window)) (err u100))
        (try! (stx-transfer? PLAY-PRICE (var-get developer-address) tx-sender))
        (ok true)
    )
)



;; Add to data maps
(define-map tier-prices 
    { tier: uint } 
    { price: uint, playtime: uint }
)

;; Add function
(define-public (start-tiered-session (tier-id uint))
    (let 
        ((tier-info (unwrap! (map-get? tier-prices {tier: tier-id}) (err u101))))
        (try! (stx-transfer? (get price tier-info) tx-sender (var-get developer-address)))
        (ok true)
    )
)




;; Add to data maps
(define-map player-achievements 
    { player: principal } 
    { achievements: (list 10 uint) }
)

;; Add function
(define-public (unlock-achievement (achievement-id uint))
    (let
        ((current-achievements (default-to {achievements: (list)} (map-get? player-achievements {player: tx-sender}))))
        (map-set player-achievements 
            {player: tx-sender}
            {achievements: (unwrap! (as-max-len? (append (get achievements current-achievements) achievement-id) u10) (err u102))})
        (ok true)
    )
)




;; Add to data vars
(define-data-var subscription-price uint u10000000) ;; 10 STX
(define-map subscriptions 
    { subscriber: principal } 
    { expiry: uint }
)

;; Add function
(define-public (purchase-subscription)
    (begin
        (try! (stx-transfer? (var-get subscription-price) tx-sender (var-get developer-address)))
        (map-set subscriptions 
            {subscriber: tx-sender}
            {expiry: (+ stacks-block-height u1440)}) ;; 1 day subscription
        (ok true)
    )
)



;; Add to data maps
(define-map referral-rewards 
    { referrer: principal } 
    { total-rewards: uint }
)

;; Add function
(define-public (play-with-referral (referrer principal))
    (begin
        (try! (stx-transfer? PLAY-PRICE tx-sender (var-get developer-address)))
        (try! (stx-transfer? (/ PLAY-PRICE u10) (var-get developer-address) referrer))
        (ok true)
    )
)




;; Add to data maps
(define-map player-stats
    { player: principal }
    { total-time: uint, high-score: uint }
)

;; Add function
(define-public (update-player-stats (play-time uint) (score uint))
    (let
        ((current-stats (default-to {total-time: u0, high-score: u0} (map-get? player-stats {player: tx-sender}))))
        (map-set player-stats
            {player: tx-sender}
            {
                total-time: (+ (get total-time current-stats) play-time),
                high-score: (if (> score (get high-score current-stats)) score (get high-score current-stats))
            }
        )
        (ok true)
    )
)



;; Add to data maps
(define-map game-ratings
    { player: principal }
    { rating: uint }
)

;; Add function
(define-public (rate-game (rating uint))
    (begin
        (asserts! (<= rating u5) (err u103))
        (map-set game-ratings
            {player: tx-sender}
            {rating: rating}
        )
        (ok true)
    )
)
