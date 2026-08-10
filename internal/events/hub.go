package events

import (
	"sync"

	"github.com/caigg188/vback/internal/domain"
)

type Hub struct {
	mu   sync.Mutex
	subs map[string]map[chan domain.Event]struct{}
}

func New() *Hub { return &Hub{subs: make(map[string]map[chan domain.Event]struct{})} }

func (h *Hub) Subscribe(runID string) (<-chan domain.Event, func()) {
	h.mu.Lock()
	defer h.mu.Unlock()
	ch := make(chan domain.Event, 32)
	if h.subs[runID] == nil {
		h.subs[runID] = make(map[chan domain.Event]struct{})
	}
	h.subs[runID][ch] = struct{}{}
	return ch, func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		if _, ok := h.subs[runID][ch]; ok {
			delete(h.subs[runID], ch)
			close(ch)
		}
	}
}

func (h *Hub) Publish(event domain.Event) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.subs[event.RunID] {
		select {
		case ch <- event:
		default:
		}
	}
}
