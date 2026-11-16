package main

// Releasing an account has the same durable end state as inactivity expiry.
// Only the exact owning key can select it; retries of tombstoned keys succeed
// without touching a subsequent owner of the freed callsign.
func (s *infiniteServer) releaseAccount(token string) error {
	hash, valid := publicTokenHash(token)
	if !valid {
		return errOnlineOwnerInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return errAccountServerClosed
	}
	r := s.hub.callsigns
	r.mu.Lock()
	if r.expired[hash] {
		r.expiryMu.Lock()
		pending := r.expirationPending
		r.expirationPending = make(map[string]bool)
		r.expiryMu.Unlock()
		r.mu.Unlock()
		s.retireExpiredAccounts(pending, "This callsign was released. Choose a callsign to start a new account.")
		return nil
	}
	if r.revoked[hash] {
		r.mu.Unlock()
		return errOnlineOwnerRevoked
	}
	if !r.owners[hash] {
		r.mu.Unlock()
		return errOnlineOwnerInvalid
	}
	if err := r.removeAccountsLocked([]string{hash}); err != nil {
		r.mu.Unlock()
		return err
	}
	r.expiryMu.Lock()
	pending := r.expirationPending
	r.expirationPending = make(map[string]bool)
	r.expiryMu.Unlock()
	r.mu.Unlock()
	s.retireExpiredAccounts(pending, "This callsign was released. Choose a callsign to start a new account.")
	return nil
}
