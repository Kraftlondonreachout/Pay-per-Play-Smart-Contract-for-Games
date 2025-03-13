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


;; Add to data maps
(define-map tournaments 
    { tournament-id: uint } 
    { entry-fee: uint, prize-pool: uint, participants: (list 50 principal), active: bool }
)

(define-data-var tournament-counter uint u0)

;; Add functions
(define-public (create-tournament (entry-fee uint))
    (let
        ((tournament-id (var-get tournament-counter)))
        (map-set tournaments
            {tournament-id: tournament-id}
            {
                entry-fee: entry-fee,
                prize-pool: u0,
                participants: (list),
                active: true
            }
        )
        (var-set tournament-counter (+ tournament-id u1))
        (ok tournament-id)
    )
)

(define-public (join-tournament (tournament-id uint))
    (let
        ((tournament (unwrap! (map-get? tournaments {tournament-id: tournament-id}) (err u200))))
        (try! (stx-transfer? (get entry-fee tournament) tx-sender (var-get developer-address)))
        (map-set tournaments
            {tournament-id: tournament-id}
            (merge tournament 
                {
                    prize-pool: (+ (get prize-pool tournament) (get entry-fee tournament)),
                    participants: (unwrap! (as-max-len? (append (get participants tournament) tx-sender) u50) (err u201))
                }
            )
        )
        (ok true)
    )
)


;; Add to data maps
(define-map leaderboard
    { season: uint }
    { top-players: (list 100 {player: principal, score: uint}) }
)

(define-data-var current-season uint u1)

(define-public (submit-score (score uint))
    (let
        ((season (var-get current-season)))
        (map-set leaderboard
            {season: season}
            {top-players: (unwrap! (as-max-len? 
                (append (default-to (list) (get top-players (map-get? leaderboard {season: season}))) 
                {player: tx-sender, score: score}) 
                u100) (err u301))}
        )
        (ok true)
    )
)


;; Add to data maps
(define-map game-items
    { item-id: uint }
    { price: uint, name: (string-ascii 50), available: bool }
)

(define-map player-inventory
    { player: principal }
    { owned-items: (list 100 uint) }
)

(define-public (purchase-item (item-id uint))
    (let
        ((item (unwrap! (map-get? game-items {item-id: item-id}) (err u400))))
        (asserts! (get available item) (err u401))
        (try! (stx-transfer? (get price item) tx-sender (var-get developer-address)))
        (map-set player-inventory
            {player: tx-sender}
            {owned-items: (unwrap! (as-max-len? 
                (append (default-to (list) (get owned-items (map-get? player-inventory {player: tx-sender}))) 
                item-id) 
                u100) (err u402))}
        )
        (ok true)
    )
)


;; Add to data maps
(define-map guilds
    { guild-id: uint }
    { name: (string-ascii 50), leader: principal, members: (list 50 principal) }
)

(define-data-var guild-counter uint u0)

(define-public (create-guild (guild-name (string-ascii 50)))
    (let
        ((guild-id (var-get guild-counter)))
        (map-set guilds
            {guild-id: guild-id}
            {
                name: guild-name,
                leader: tx-sender,
                members: (list tx-sender)
            }
        )
        (var-set guild-counter (+ guild-id u1))
        (ok guild-id)
    )
)

(define-public (join-guild (guild-id uint))
    (let
        ((guild (unwrap! (map-get? guilds {guild-id: guild-id}) (err u600))))
        (map-set guilds
            {guild-id: guild-id}
            (merge guild 
                {members: (unwrap! (as-max-len? (append (get members guild) tx-sender) u50) (err u601))}
            )
        )
        (ok true)
    )
)




;; Add to data maps
(define-map trade-offers
    { trade-id: uint }
    { 
        from: principal,
        to: principal,
        item-offered: uint,
        item-requested: uint,
        status: (string-ascii 20)
    }
)

(define-data-var trade-counter uint u0)

(define-public (create-trade-offer (to principal) (item-offered uint) (item-requested uint))
    (let
        ((trade-id (var-get trade-counter)))
        (map-set trade-offers
            {trade-id: trade-id}
            {
                from: tx-sender,
                to: to,
                item-offered: item-offered,
                item-requested: item-requested,
                status: "pending"
            }
        )
        (var-set trade-counter (+ trade-id u1))
        (ok trade-id)
    )
)



;; Add to data maps
(define-map game-events
    { event-id: uint }
    {
        name: (string-ascii 50),
        reward: uint,
        start-block: uint,
        end-block: uint,
        participants: (list 100 principal)
    }
)

(define-data-var event-counter uint u0)

(define-public (create-game-event (name (string-ascii 50)) (reward uint) (duration uint))
    (let
        ((event-id (var-get event-counter)))
        (map-set game-events
            {event-id: event-id}
            {
                name: name,
                reward: reward,
                start-block: stacks-block-height,
                end-block: (+ stacks-block-height duration),
                participants: (list)
            }
        )
        (var-set event-counter (+ event-id u1))
        (ok event-id)
    )
)
