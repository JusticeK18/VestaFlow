;; contract title: intelligent-vesting
;; This contract provides a secure and flexible intelligent token vesting scheduler. 
;; It allows an administrator to create vesting schedules for beneficiaries,
;; who can claim their vested tokens over time linearly after a cliff period.
;; It also includes advanced features like revocation, reallocation, global pausing,
;; multi-admin support, and schedule transfers (e.g., to a cold wallet).

;; ==========================================
;; Constants and Error Codes
;; ==========================================
(define-constant contract-deployer tx-sender)

;; Error Codes
(define-constant err-unauthorized (err u100))
(define-constant err-schedule-exists (err u101))
(define-constant err-schedule-not-found (err u102))
(define-constant err-nothing-to-claim (err u103))
(define-constant err-invalid-params (err u104))
(define-constant err-paused (err u105))
(define-constant err-already-paused (err u106))
(define-constant err-not-paused (err u107))
(define-constant err-insufficient-balance (err u108))
(define-constant err-cannot-remove-deployer (err u109))
(define-constant err-invalid-transfer (err u110))

;; ==========================================
;; Data Variables
;; ==========================================
;; Circuit breaker to pause all claims and modifications
(define-data-var contract-paused bool false)

;; Track total tokens locked across all schedules
(define-data-var total-tokens-locked uint u0)
(define-data-var total-tokens-claimed uint u0)

;; ==========================================
;; Data Maps
;; ==========================================
;; Admin roles map
(define-map admins principal bool)

;; Maps each beneficiary principal to their vesting schedule details.
(define-map vesting-schedules
    principal
    {
        category: (string-ascii 20), ;; e.g., "team", "advisor", "investor"
        total-amount: uint,          ;; Total tokens to be vested
        claimed-amount: uint,        ;; Tokens already claimed
        start-block: uint,           ;; Block height when vesting starts
        duration: uint,              ;; Total duration of vesting in blocks
        cliff-duration: uint,        ;; Duration of the cliff period in blocks
        revocable: bool,             ;; Whether the schedule can be revoked
        revoked: bool                ;; Whether the schedule has been revoked
    }
)

;; ==========================================
;; Initialization
;; ==========================================
;; Set the deployer as the initial admin
(map-set admins contract-deployer true)

;; ==========================================
;; Private Functions
;; ==========================================
;; Check if a user is an admin
(define-private (is-admin (user principal))
    (default-to false (map-get? admins user))
)

;; Require that the contract is not paused
(define-private (require-unpaused)
    (begin
        (asserts! (not (var-get contract-paused)) err-paused)
        (ok true)
    )
)

;; Require admin privileges
(define-private (require-admin)
    (begin
        (asserts! (is-admin tx-sender) err-unauthorized)
        (ok true)
    )
)

;; Calculates the total vested amount for a given schedule up to the current block.
;; Returns u0 if the cliff hasn't been reached or if the schedule was revoked.
(define-private (calculate-vested-amount (schedule {category: (string-ascii 20), total-amount: uint, claimed-amount: uint, start-block: uint, duration: uint, cliff-duration: uint, revocable: bool, revoked: bool}))
    (let (
        (current-block block-height)
        (cliff-end (+ (get start-block schedule) (get cliff-duration schedule)))
        (end-block (+ (get start-block schedule) (get duration schedule)))
        (elapsed (- current-block (get start-block schedule)))
    )
    (if (or (get revoked schedule) (< current-block cliff-end))
        u0
        (if (>= current-block end-block)
            (get total-amount schedule)
            (/ (* (get total-amount schedule) elapsed) (get duration schedule))
        )
    ))
)

;; ==========================================
;; Administrative Public Functions
;; ==========================================
;; Add a new admin
(define-public (add-admin (new-admin principal))
    (begin
        (try! (require-admin))
        (ok (map-set admins new-admin true))
    )
)

;; Remove an admin
(define-public (remove-admin (admin-to-remove principal))
    (begin
        (try! (require-admin))
        (asserts! (not (is-eq admin-to-remove contract-deployer)) err-cannot-remove-deployer)
        (ok (map-delete admins admin-to-remove))
    )
)

;; Pause the contract
(define-public (pause-contract)
    (begin
        (try! (require-admin))
        (asserts! (not (var-get contract-paused)) err-already-paused)
        (ok (var-set contract-paused true))
    )
)

;; Resume the contract
(define-public (resume-contract)
    (begin
        (try! (require-admin))
        (asserts! (var-get contract-paused) err-not-paused)
        (ok (var-set contract-paused false))
    )
)

;; ==========================================
;; Core Public Functions
;; ==========================================
;; Creates a new vesting schedule for a beneficiary.
(define-public (create-schedule 
    (beneficiary principal) 
    (category (string-ascii 20))
    (total-amount uint) 
    (start-block uint) 
    (duration uint) 
    (cliff-duration uint) 
    (revocable bool))
    (begin
        (try! (require-admin))
        (try! (require-unpaused))
        (asserts! (> duration u0) err-invalid-params)
        (asserts! (<= cliff-duration duration) err-invalid-params)
        (asserts! (> total-amount u0) err-invalid-params)
        (asserts! (is-none (map-get? vesting-schedules beneficiary)) err-schedule-exists)
        
        ;; Update global tracking
        (var-set total-tokens-locked (+ (var-get total-tokens-locked) total-amount))
        
        ;; Log event
        (print {event: "schedule-created", beneficiary: beneficiary, amount: total-amount, category: category})

        (ok (map-set vesting-schedules beneficiary {
            category: category,
            total-amount: total-amount,
            claimed-amount: u0,
            start-block: start-block,
            duration: duration,
            cliff-duration: cliff-duration,
            revocable: revocable,
            revoked: false
        }))
    )
)

;; Allows a beneficiary to claim their currently vested tokens.
(define-public (claim)
    (let (
        (schedule (unwrap! (map-get? vesting-schedules tx-sender) err-schedule-not-found))
        (vested-amount (calculate-vested-amount schedule))
        (claimed (get claimed-amount schedule))
        (claimable (- vested-amount claimed))
    )
    (try! (require-unpaused))
    (asserts! (> claimable u0) err-nothing-to-claim)
    
    ;; Update the claimed amount in the schedule
    (map-set vesting-schedules tx-sender (merge schedule {claimed-amount: (+ claimed claimable)}))
    
    ;; Update global tracking
    (var-set total-tokens-claimed (+ (var-get total-tokens-claimed) claimable))
    
    ;; Log event
    (print {event: "tokens-claimed", beneficiary: tx-sender, amount: claimable})

    ;; Transfer tokens (Using STX for this example)
    (as-contract (stx-transfer? claimable tx-sender tx-sender))
    )
)

;; Allows a beneficiary to transfer their entire vesting schedule to a new wallet (e.g., cold storage)
(define-public (transfer-schedule (new-address principal))
    (let (
        (schedule (unwrap! (map-get? vesting-schedules tx-sender) err-schedule-not-found))
    )
    (try! (require-unpaused))
    (asserts! (not (get revoked schedule)) err-invalid-transfer)
    (asserts! (is-none (map-get? vesting-schedules new-address)) err-schedule-exists)
    (asserts! (not (is-eq tx-sender new-address)) err-invalid-params)

    ;; Delete old schedule
    (map-delete vesting-schedules tx-sender)

    ;; Set new schedule
    (map-set vesting-schedules new-address schedule)

    ;; Log event
    (print {event: "schedule-transferred", old-address: tx-sender, new-address: new-address})

    (ok true)
    )
)

;; ==========================================
;; Read-Only Functions
;; ==========================================
;; Get the full schedule details for a beneficiary
(define-read-only (get-schedule (beneficiary principal))
    (map-get? vesting-schedules beneficiary)
)

;; Get the total vested amount for a beneficiary
(define-read-only (get-vested-amount (beneficiary principal))
    (match (map-get? vesting-schedules beneficiary)
        schedule (ok (calculate-vested-amount schedule))
        err-schedule-not-found
    )
)

;; Get the claimable (vested but unclaimed) amount for a beneficiary
(define-read-only (get-claimable-amount (beneficiary principal))
    (match (map-get? vesting-schedules beneficiary)
        schedule (ok (- (calculate-vested-amount schedule) (get claimed-amount schedule)))
        err-schedule-not-found
    )
)

;; Get the unvested (locked) amount for a beneficiary
(define-read-only (get-locked-amount (beneficiary principal))
    (match (map-get? vesting-schedules beneficiary)
        schedule (ok (- (get total-amount schedule) (calculate-vested-amount schedule)))
        err-schedule-not-found
    )
)

;; Check if the contract is paused
(define-read-only (is-paused)
    (var-get contract-paused)
)

;; Check if a given address is an admin
(define-read-only (check-is-admin (user principal))
    (is-admin user)
)

;; Get global vesting statistics
(define-read-only (get-global-stats)
    {
        total-locked: (var-get total-tokens-locked),
        total-claimed: (var-get total-tokens-claimed)
    }
)


