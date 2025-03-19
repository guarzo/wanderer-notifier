# Wanderer Notifier Documentation

This branch contains the GitHub Pages documentation website for the Wanderer Notifier project.

## Website Structure

- `index.md`: Main landing page
- `notifications.md`: Details about notification types
- `license.md`: License comparison and features
- `_layouts/default.html`: Custom layout template
- `assets/css/style.scss`: Custom styling
- `assets/images/`: Screenshots and images

## Local Development

To test the site locally:

1. Install Ruby and Jekyll: https://jekyllrb.com/docs/installation/
2. Clone this branch: `git clone -b gh-pages https://github.com/guarzo/wanderer-notifier.git`
3. Navigate to the project directory: `cd wanderer-notifier`
4. Install dependencies: `bundle install`
5. Start the local server: `bundle exec jekyll serve`
6. Visit `http://localhost:4000` in your browser

## Updating the Website

The website is automatically updated when changes are pushed to the gh-pages branch. The GitHub Action workflow in the main branch deploys to this branch when triggered.

## Image References

The following image placeholders need to be replaced with actual screenshots:

- `assets/images/paid-kill.png`: Licensed kill notification example
- `assets/images/free-kill.png`: Free kill notification example
- `assets/images/paid-character.png`: Licensed character notification example
- `assets/images/free-character.png`: Free character notification example
- `assets/images/paid-system.png`: Licensed system notification example
- `assets/images/free-system.png`: Free system notification example 