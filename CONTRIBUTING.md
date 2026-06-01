# Contributing to Sabha

Thanks for your interest in improving Sabha. This guide covers the basics.

## Getting started

```bash
bin/setup   # Install dependencies, prepare the database, build CSS
bin/dev     # Start the development server
```

You'll need Ruby (see `.ruby-version`), Node (see `.node-version`), and pnpm.

## Making changes

1. Fork the repo and create a branch off `main`.
2. Make your change. Keep it focused — one concern per pull request.
3. Add or update tests for anything you change.
4. Run the test suite and make sure it passes:

   ```bash
   bin/rails test
   ```

5. Open a pull request with a clear description of what changed and why.

RuboCop runs automatically on commit and Brakeman on push (via lefthook), so style
and basic security checks are handled for you.

## What we're looking for

Sabha aims to be **warm, simple, and reliable**. Prefer clarity over cleverness, and
lean on Rails conventions — fat models, thin RESTful controllers, no service-layer
bloat. See [CLAUDE.md](CLAUDE.md) for the code quality standards we hold ourselves to.

## Reporting bugs and requesting features

Open an issue. For bugs, include steps to reproduce, what you expected, and what
happened instead. For security issues, please **don't** open a public issue — see
[SECURITY.md](SECURITY.md) if present, or email the maintainers privately.

## License

By contributing, you agree that your contributions to the core application are
licensed under the MIT License. Contributions under `saas/` fall under the license in
[`saas/LICENSE`](saas/LICENSE). See [LICENSE.md](LICENSE.md) for details.
