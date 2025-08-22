;; ChainWeave Oracle Registry Contract
;; Directory and metadata management for Oracle operators

(define-map oracle-profiles
  principal
  {
    name: (string-ascii 64),
    description: (string-ascii 256),
    website: (string-ascii 128),
    contact: (string-ascii 64),
    supported-chains: (list 20 uint),
    supported-assets: (list 50 (string-ascii 32)),
    registration-date: uint,
    last-update: uint,
    verified: bool
  }
)

(define-map oracle-metrics
  principal
  {
    total-reports: uint,
    accurate-reports: uint,
    late-reports: uint,
    missed-reports: uint,
    uptime-percentage: uint,
    average-response-time: uint
  }
)

(define-public (register-oracle-profile 
  (name (string-ascii 64))
  (description (string-ascii 256))
  (website (string-ascii 128))
  (contact (string-ascii 64))
  (supported-chains (list 20 uint))
  (supported-assets (list 50 (string-ascii 32)))
)
  (begin
    (map-set oracle-profiles tx-sender {
      name: name,
      description: description,
      website: website,
      contact: contact,
      supported-chains: supported-chains,
      supported-assets: supported-assets,
      registration-date: stacks-block-height,
      last-update: stacks-block-height,
      verified: false
    })
    
    (map-set oracle-metrics tx-sender {
      total-reports: u0,
      accurate-reports: u0,
      late-reports: u0,
      missed-reports: u0,
      uptime-percentage: u100,
      average-response-time: u0
    })
    
    (ok true)
  )
)

(define-read-only (get-oracle-profile (oracle principal))
  (map-get? oracle-profiles oracle)
)

(define-read-only (get-oracle-metrics (oracle principal))
  (map-get? oracle-metrics oracle)
)
