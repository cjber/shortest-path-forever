### Fixed

- **Waypoint UI can lead from the first turn.** When Waypoint UI is loaded, journeys send it the next turn even if it was not already tracking a pin. This also works with *Mark only where steps end* on. Turn off Waypoint UI's own pathfinding to follow the journey's directions.
