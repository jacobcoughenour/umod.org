#require 'discourse_api'
require 'json'
require 'kramdown'
require 'net/http'
require 'open-uri'
#require 'patreon'
require 'sanitize'

# TODO: Check if from Netlify and use WEBHOOK_BODY env to see what content to change

module Jekyll
  # The PluginPage class creates a single ingredients, plugin, or plugins page
  class PluginPage < Page
    # The resultant relative URL of where the published file will end up
    # Added for use by a sitemap generator
    attr_accessor :dest_url

    # Initialize a new page
    # site - The Site object
    # base - The String path to the source
    # dest_dir  - The String path between the dest and the file
    # dest_name - The String name of the destination file (e.g. index.html or myplugin.html)
    # src_name - The String filename of the source page file, minus the markdown or html extension
    def initialize(site, base, dest_dir, dest_name, src_name)
      @site = site
      @base = base
      @dir  = dest_dir
      @dest_dir = dest_dir
      @dest_name = dest_name
      @dest_url = File.join('/', dest_dir)

      src_file = File.join(base, '_layouts', "#{src_name}.markdown")
      src_name_with_ext = "#{src_name}.markdown" if File.exists?(src_file)
      src_name_with_ext ||= "#{src_name}.html"
      self.process(src_name_with_ext)

      # Read the YAML from the specified layout template
      self.read_yaml(File.join(base, '_layouts'), src_name_with_ext)
    end

    # Attach our data to the global page variable. This allows pages to see this data
    def set_data(label, data)
      self.data[label] = data
    end

    # Attach our data to the global page variable. This allows pages to see this data
    # Use to set plugin. Also sets the page title
    def set_page_data(plugin, prev_plugin, next_plugin)
      # Set the plugin instances
      self.data['plugin'] = plugin
      self.data['plugin_prev'] = prev_plugin
      self.data['plugin_next'] = next_plugin

      # Set the humanized title for this page
      self.data['title'] = plugin['title']
      puts "Plugin page title set to: #{plugin['title']}"

      # Set the brief description for this page
      self.data['description'] = plugin['description']
    end

    # Override so that we can control where the destination file goes
    def destination(dest)
      # The URL needs to be unescaped in order to preserve the correct filename
      path = File.join(dest, @dest_dir, @dest_name)
      path
    end
  end

  # The Site class is a built-in Jekyll class with access to global site config information
  class Site
    def get_remote_file(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      response
    end

    def sanitize_readme(input, repo)
        # Remove redundant headings with repo's name
        readme = input.body.gsub('# ' + repo['name'], '') \
        # Remove redundant descriptions that match existing
        .gsub(repo['description'], '') \
        # Remove any remote images or badges from description
        .gsub(/\[?\!\[[\w\s?]+\]?\(.*\)/, '') \
        # Remove any whitespace from start or end of string
        .strip
        readme
    end

    # Creates instances of PluginPage, renders then, and writes the output to a file
    # Will create a page for the plugins index and each plugin
    def write_all_plugin_files
      # Read the JSON data. This is our 'database'
      plugins_org = self.config['plugins_org']
      if !plugins_org
        return
      end

      token = ENV['JEKYLL_GITHUB_TOKEN'] || ENV['GITHUB_TOKEN']

      page = 1
      repos = []
      while true
        puts "Getting page #{page.to_s} of plugin repositories from GitHub..."
        url = 'https://api.github.com/orgs/' + plugins_org + '/repos?per_page=100&page=' + page.to_s
        response = JSON.load(open(url, !token.nil? && !token.empty? ? { "Authorization" => "token " + token } : nil))
        break if response.size == 0
        response.each { |h| repos << h }
        puts "Found #{response.size.to_s} more plugins to generate pages for"
        page += 1
      end
      repos = repos.select { |p| !p['language'].nil? }
      repos = repos.sort_by { |p| p['name'] }
      repos.each do |repo|
        # Set humanized title and clean description
        repo['title'] = repo['name'].humanize
        repo['description'] = Sanitize.clean(repo['description']).chomp('.')

        # Set the readme variable, if available
        readme_url = 'https://raw.githubusercontent.com/umods/' + repo['name'] + '/master/README.md'
        readme_response = get_remote_file(readme_url)
        if readme_response.code == '200' && !readme_response.body.nil?
          puts "Found README.md, setting plugin.readme for plugin #{repo['name']}"
          repo['readme'] = Kramdown::Document.new(sanitize_readme(readme_response, repo)).to_html
        end

        # Set the icon.png URL, if available
        icon_url = 'https://raw.githubusercontent.com/umods/' + repo['name'] + '/master/icon.png'
        icon_response = get_remote_file(icon_url)
        if icon_response.code == '200'
          puts "Found icon.png, setting plugin.icon_url for plugin #{repo['name']}"
          repo['icon_url'] = icon_url
        end
      end

      # Write all of the plugin pages
      puts "Plugins data read: found #{repos.length} plugins"
      write_plugins_index(repos, 'plugins')
      write_plugin_pages(repos, 'plugins')
    end

    # Write a plugins/index.html page
    def write_plugins_index(data, dest_dir)
      index = PluginPage.new(self, self.source, dest_dir, 'index.html', 'plugins')
      index.set_data('plugins', data)
      index.render(self.layouts, site_payload)
      index.write(self.dest)
      self.pages << index
    end

    # Loops through the list of plugin and processes each one
    def write_plugin_pages(plugins, dest_dir)
      if plugins && plugins.length > 0
        if self.layouts.key? 'plugin'
          plugins.each_with_index do |plugin, index|
            write_plugin_page(plugin, dest_dir, (index > 0) ? plugins[index-1] : nil, plugins[index+1])
          end
        else
          throw "No 'plugin' layout found."
        end
      end
    end

    # Write a plugins/plugin-name/index.html page
    def write_plugin_page(plugin, dest_dir, prev_plugin, next_plugin)
      # Attach our plugin data to global site variable. This allows pages to see this plugin's data
      puts "Generating page for plugin #{plugin['name']} (#{plugin['id']})"
      page = PluginPage.new(self, self.source, File.join(dest_dir, plugin['name']), 'index.html', 'plugin')
      page.set_page_data(plugin, prev_plugin, next_plugin)
      page.render(self.layouts, site_payload)
      page.write(self.dest)
      self.pages << page

      # Download the plugin file to serve directly
      if !plugin['language'].nil?
        filename = plugin['name'] + '.cs' # TODO: Handle file extension dynamically
        path = File.join(dest_dir, plugin['name'])
        download = open('https://raw.githubusercontent.com/umods/' + plugin['name'] + '/master/' + filename) {|f| f.read }
        if !download.nil?
          unless File.directory?(File.join(self.source, path))
            FileUtils.mkdir_p(File.join(self.source, path))
          end
          File.write(File.join(self.source, File.join(path, filename)), download)
          self.static_files << StaticFile.new(self, self.source, path, filename)
        end
      end

      #create_forums_category(plugin)
    end
=begin
    def create_forums_category(plugin)
      discourse = DiscourseApi::Client.new("https://forums.umod.org")
      discourse.api_key = ENV['DISCOURSE_API_KEY']
      discourse.api_username = "system"
      discourse.ssl(verify: false)

      plugin_name = plugin['name'].humanize

      # TODO: Check if category exists before attempting to create
      #categories = JSON.parse(discourse.categories(parent_category_id: 21))
      #if !categories['name'].to_a.detect { |e| e['name'] == plugin_name }.nil? # TODO: Fix this code and check
      #  return
      #end

      # Create new forum category for plugin
      new_category = discourse.create_category(
        name: plugin_name,
        color: "AB9364",
        text_color: "FFFFFF",
        parent_category_id: 21 # Plugin Support category
      )
      puts "Created category: #{new_category}"

      # Update new category with description
      updated_category = discourse.update_category(
        id: new_category['id'],
        description: "Support and discussion for #{plugin['name']}. Visit the plugin's page at https://umod.org/plugins/#{plugin['name']}/."
      )
      puts "Updated category: #{updated_category}"
    end
=end
  end

  # Jekyll hook - the generate method is called by Jekyll, and generates all of the plugin pages
  class PageGenerator < Generator
    safe true

    def generate(site)
      site.write_all_plugin_files
    end
  end
end
