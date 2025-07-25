(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_INSUFFICIENT_BALANCE (err u104))
(define-constant ERR_HARVEST_NOT_VERIFIED (err u105))
(define-constant ERR_SEASON_NOT_ACTIVE (err u106))
(define-constant ERR_INVALID_SEASON (err u107))

(define-constant CONTRACT_OWNER tx-sender)
(define-constant TOKEN_NAME "Yieldbit")
(define-constant TOKEN_SYMBOL "YBT")
(define-constant TOKEN_DECIMALS u6)
(define-constant BLOCKS_PER_SEASON u52560)

(define-data-var total-supply uint u0)
(define-data-var current-season uint u1)
(define-data-var season-start-block uint u0)
(define-data-var total-verified-yield uint u0)

(define-map token-balances principal uint)
(define-map token-allowances {owner: principal, spender: principal} uint)

(define-map farmers 
    principal 
    {
        registered: bool,
        total-harvests: uint,
        reputation-score: uint,
        last-harvest-block: uint
    }
)

(define-map harvests 
    {farmer: principal, season: uint, harvest-id: uint}
    {
        yield-amount: uint,
        crop-type: (string-ascii 50),
        verified: bool,
        verification-block: uint,
        verifier: (optional principal),
        tokens-issued: uint
    }
)

(define-map season-stats
    uint
    {
        total-yield: uint,
        total-farmers: uint,
        tokens-distributed: uint,
        harvest-count: uint,
        season-end-block: uint
    }
)

(define-map harvest-counters principal uint)

(define-read-only (get-name)
    (ok TOKEN_NAME)
)

(define-read-only (get-symbol)
    (ok TOKEN_SYMBOL)
)

(define-read-only (get-decimals)
    (ok TOKEN_DECIMALS)
)

(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

(define-read-only (get-balance (account principal))
    (ok (default-to u0 (map-get? token-balances account)))
)

(define-read-only (get-allowance (owner principal) (spender principal))
    (ok (default-to u0 (map-get? token-allowances {owner: owner, spender: spender})))
)

(define-read-only (get-current-season)
    (ok (var-get current-season))
)

(define-read-only (get-farmer-info (farmer principal))
    (map-get? farmers farmer)
)

(define-read-only (get-harvest-info (farmer principal) (season uint) (harvest-id uint))
    (map-get? harvests {farmer: farmer, season: season, harvest-id: harvest-id})
)

(define-read-only (get-season-stats (season uint))
    (map-get? season-stats season)
)

(define-read-only (is-season-active)
    (let ((current-block stacks-block-height)
          (season-start (var-get season-start-block)))
        (< (- current-block season-start) BLOCKS_PER_SEASON)
    )
)

(define-public (register-farmer)
    (let ((farmer tx-sender))
        (asserts! (is-none (map-get? farmers farmer)) ERR_ALREADY_EXISTS)
        (map-set farmers farmer {
            registered: true,
            total-harvests: u0,
            reputation-score: u100,
            last-harvest-block: u0
        })
        (ok true)
    )
)

(define-public (report-harvest (yield-amount uint) (crop-type (string-ascii 50)))
    (let ((farmer tx-sender)
          (current-season-val (var-get current-season))
          (harvest-counter (default-to u0 (map-get? harvest-counters farmer)))
          (new-harvest-id (+ harvest-counter u1)))
        (asserts! (> yield-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (is-some (map-get? farmers farmer)) ERR_NOT_FOUND)
        (asserts! (is-season-active) ERR_SEASON_NOT_ACTIVE)
        
        (map-set harvest-counters farmer new-harvest-id)
        (map-set harvests {farmer: farmer, season: current-season-val, harvest-id: new-harvest-id} {
            yield-amount: yield-amount,
            crop-type: crop-type,
            verified: false,
            verification-block: u0,
            verifier: none,
            tokens-issued: u0
        })
        
        (map-set farmers farmer 
            (merge (unwrap-panic (map-get? farmers farmer)) 
                   {total-harvests: (+ (get total-harvests (unwrap-panic (map-get? farmers farmer))) u1),
                    last-harvest-block: stacks-block-height}))
        
        (ok new-harvest-id)
    )
)

(define-public (verify-harvest (farmer principal) (season uint) (harvest-id uint))
    (let ((verifier tx-sender)
          (harvest-key {farmer: farmer, season: season, harvest-id: harvest-id})
          (harvest-data (unwrap! (map-get? harvests harvest-key) ERR_NOT_FOUND)))
        (asserts! (or (is-eq verifier CONTRACT_OWNER) (is-farmer-verified verifier)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get verified harvest-data)) ERR_ALREADY_EXISTS)
        
        (let ((yield-amount (get yield-amount harvest-data))
              (tokens-to-issue (calculate-tokens-for-yield yield-amount)))
            
            (map-set harvests harvest-key 
                (merge harvest-data {
                    verified: true,
                    verification-block: stacks-block-height,
                    verifier: (some verifier),
                    tokens-issued: tokens-to-issue
                }))
            
            (unwrap! (mint-tokens farmer tokens-to-issue) ERR_NOT_FOUND)
            (var-set total-verified-yield (+ (var-get total-verified-yield) yield-amount))
            
            (update-farmer-reputation farmer true)
            (update-season-stats season yield-amount tokens-to-issue)
            (ok tokens-to-issue)
        )
    )
)

(define-public (transfer (amount uint) (recipient principal))
    (let ((sender tx-sender)
          (sender-balance (unwrap! (get-balance sender) ERR_NOT_FOUND)))
        ;; (asserts! (>= (unwrap-panic sender-balance) amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; (map-set token-balances sender (- (unwrap-panic sender-balance) amount))
        (map-set token-balances recipient 
            (+ (default-to u0 (map-get? token-balances recipient)) amount))
        
        (ok true)
    )
)

(define-public (approve (spender principal) (amount uint))
    (let ((owner tx-sender))
        (map-set token-allowances {owner: owner, spender: spender} amount)
        (ok true)
    )
)

(define-public (transfer-from (owner principal) (recipient principal) (amount uint))
    (let ((spender tx-sender)
          (allowance (unwrap! (get-allowance owner spender) ERR_NOT_FOUND))
          (owner-balance (unwrap! (get-balance owner) ERR_NOT_FOUND)))
        ;; (asserts! (>= (unwrap-panic allowance) amount) ERR_NOT_AUTHORIZED)
        ;; (asserts! (>= (unwrap-panic owner-balance) amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; (map-set token-allowances {owner: owner, spender: spender} (- (unwrap-panic allowance) amount))
        ;; (map-set token-balances owner (- (unwrap-panic owner-balance) amount))
        (map-set token-balances recipient 
            (+ (default-to u0 (map-get? token-balances recipient)) amount))
        
        (ok true)
    )
)

(define-public (advance-season)
    (let ((current-block stacks-block-height)
          (season-start (var-get season-start-block))
          (current-season-val (var-get current-season)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (>= (- current-block season-start) BLOCKS_PER_SEASON) ERR_SEASON_NOT_ACTIVE)
        
        (finalize-season current-season-val)
        (var-set current-season (+ current-season-val u1))
        (var-set season-start-block current-block)
        (ok (+ current-season-val u1))
    )
)

(define-public (purchase-tokens (stx-amount uint))
    (let ((buyer tx-sender)
          (token-rate u1000)
          (tokens-to-mint (* stx-amount token-rate)))
        (asserts! (> stx-amount u0) ERR_INVALID_AMOUNT)
        (try! (stx-transfer? stx-amount buyer CONTRACT_OWNER))
        (unwrap! (mint-tokens buyer tokens-to-mint) ERR_NOT_FOUND)
        (ok tokens-to-mint)
    )
)

(define-private (mint-tokens (recipient principal) (amount uint))
    (let ((current-balance (default-to u0 (map-get? token-balances recipient))))
        (map-set token-balances recipient (+ current-balance amount))
        (var-set total-supply (+ (var-get total-supply) amount))
        (ok true)
    )
)

(define-private (calculate-tokens-for-yield (yield-amount uint))
    (* yield-amount u100)
)

(define-private (is-farmer-verified (farmer principal))
    (match (map-get? farmers farmer)
        farmer-data (and (get registered farmer-data) (>= (get reputation-score farmer-data) u75))
        false
    )
)

(define-private (update-farmer-reputation (farmer principal) (positive bool))
    (let ((farmer-data (unwrap-panic (map-get? farmers farmer)))
          (current-rep (get reputation-score farmer-data))
          (new-rep (if positive
                      (min u100 (+ current-rep u5))
                      (max u0 (- current-rep u10)))))
        (map-set farmers farmer 
            (merge farmer-data {reputation-score: new-rep}))
    )
)

(define-private (update-season-stats (season uint) (yield-amount uint) (tokens-issued uint))
    (let ((current-stats (default-to {total-yield: u0, total-farmers: u0, tokens-distributed: u0, harvest-count: u0, season-end-block: u0}
                                   (map-get? season-stats season))))
        (map-set season-stats season {
            total-yield: (+ (get total-yield current-stats) yield-amount),
            total-farmers: (get total-farmers current-stats),
            tokens-distributed: (+ (get tokens-distributed current-stats) tokens-issued),
            harvest-count: (+ (get harvest-count current-stats) u1),
            season-end-block: (get season-end-block current-stats)
        })
    )
)

(define-private (finalize-season (season uint))
    (let ((current-stats (default-to {total-yield: u0, total-farmers: u0, tokens-distributed: u0, harvest-count: u0, season-end-block: u0}
                                   (map-get? season-stats season))))
        (map-set season-stats season 
            (merge current-stats {season-end-block: stacks-block-height}))
    )
)

(define-private (min (a uint) (b uint))
    (if (<= a b) a b)
)

(define-private (max (a uint) (b uint))
    (if (>= a b) a b)
)
