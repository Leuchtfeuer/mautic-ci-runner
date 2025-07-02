# Plugin Name
## Overview / Purpose / Features
Provide a short description of the plugin's purpose, key features, and benefits.
## Requirements / Version Support
- Mautic 5.x (minimum 5.1) 
- PHP X.X or higher
## Installation
### Composer
This plugin can be installed through composer.
### Manual Installation
Alternatively, it can be installed manually, following the usual steps:
- Download the plugin
- Unzip to the Mautic `plugins` directory
- Rename folder to `BundleName`
- In the Mautic backend, go to the `Plugins` page as an administrator
- Click on the `Install/Upgrade Plugins` button to install the Plugin.
OR
- If you have shell access, execute `php bin\console cache:clear` and `php bin\console mautic:plugins:reload` to install the plugins.
## Configuration
Provide instructions on configuring the plugin post-installation.
## Usage
Explain how to use the plugin, including examples if relevant.
## Known Issues
List any current issues or limitations.
## Troubleshooting
Make sure you have not only installed but also enabled the Plugin.
If things are still funny, please try
`php bin/console cache:clear`
and
`php bin/console mautic:assets:generate`
## Change log
- https://github.com/Leuchtfeuer/`bundle-name`/releases
## Future Ideas
Mention any planned updates, features, or ideas for future development.
## Sponsoring & Commercial Support
We are continuously improving our plugins. If you are requiring priority support or custom features, please contact us at mautic-plugins@leuchtfeuer.com.
## Get Involved
Feel free to open issues or submit pull requests on [GitHub](#). Follow the contribution guidelines in `CONTRIBUTING.md`.”
## Credits
Acknowledge contributors or any libraries/resources used.
## Author
Leuchtfeuer Digital Marketing GmbH
Please raise any issues in GitHub.
For all other things, please email mautic-plugins@Leuchtfeuer.com
## License
“This plugin is licensed under the MIT License. See the `LICENSE` file for more details.”
## Resources / Further Readings
Provide links to any related resources or further readings.