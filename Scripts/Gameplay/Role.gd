class_name Role
## Shared role identifier used across every round-related system
## (RoundManager, RoleManager, SpawnManager, UI). Pulled out on its own so
## none of those systems need to depend on each other just to know what a
## "role" is — each can reference Role.HIDER / Role.HUNTER directly.
enum { NONE, HIDER, HUNTER }
