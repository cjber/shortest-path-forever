### Fixed

- Following a journey on foot uses far less processor time. As you move, the route is checked again every few seconds, and each check used to rebuild the walking map around you from scratch; it now reuses the map it already has.
