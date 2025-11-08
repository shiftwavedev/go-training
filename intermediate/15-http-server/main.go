package main

import (
	"fmt"
	"log"
	"net/http"
	"sync"
)

type User struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type UserStore struct {
	mu     sync.RWMutex
	users  map[int]User
	nextID int
}

func NewUserStore() *UserStore {
	panic("not implemented")
}

func (s *UserStore) GetAll() []User {
	panic("not implemented")
}

func (s *UserStore) Get(id int) (User, bool) {
	panic("not implemented")
}

func (s *UserStore) Create(name string) User {
	panic("not implemented")
}

func (s *UserStore) Delete(id int) bool {
	panic("not implemented")
}

type Server struct {
	store *UserStore
}

func NewServer() *Server {
	return &Server{
		store: NewUserStore(),
	}
}

func (s *Server) HandleUsers(w http.ResponseWriter, r *http.Request) {
	panic("not implemented")
}

func (s *Server) HandleUser(w http.ResponseWriter, r *http.Request) {
	panic("not implemented")
}

func LoggingMiddleware(next http.Handler) http.Handler {
	panic("not implemented")
}

func main() {
	server := NewServer()
	
	mux := http.NewServeMux()
	mux.HandleFunc("/users", server.HandleUsers)
	mux.HandleFunc("/users/", server.HandleUser)
	
	handler := LoggingMiddleware(mux)
	
	fmt.Println("Server starting on :8080")
	log.Fatal(http.ListenAndServe(":8080", handler))
}
