"""Publish only a commit that passed the repository's complete CI workflow on main."""

try:
    from tools.forever_tools.release_check import main, verified
except ModuleNotFoundError:
    from forever_tools.release_check import main, verified

__all__ = ["main", "verified"]

if __name__ == "__main__":
    main()
