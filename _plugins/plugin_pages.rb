require 'json'
require 'kramdown'
require 'net/http'
require 'open-uri'
require 'sanitize'

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
    def set_plugin_data(plugin, prev_plugin, next_plugin)
      # Set the plugin instances
      self.data['plugin'] = plugin
      self.data['plugin_prev'] = prev_plugin
      self.data['plugin_next'] = next_plugin

      # Set the humanized title for this page
      self.data['title'] = plugin['name'].humanize
      puts "Plugin page title set to: #{self.data['title']}"

      # Set the brief description for this page
      self.data['description'] = Sanitize.clean(plugin['description']).chomp('.')

      # Set the additional information for this page
      readme_url = 'https://raw.githubusercontent.com/umods/' + plugin['name'] + '/master/README.md'
      readme_response = get_remote_file(readme_url)
      if readme_response.code == '200' && !readme_response.body.nil?
        puts "Found README.md, setting page.plugin.readme for plugin #{plugin['name']}"
        self.data['plugin']['readme'] = Kramdown::Document.new(sanitize_readme(readme_response, plugin)).to_html
      end

      # Set the icon.png if it is available
      icon_url = 'https://raw.githubusercontent.com/umods/' + plugin['name'] + '/master/icon.png'
      icon_response = get_remote_file(icon_url)
      if icon_response.code == '200'
        puts "Found icon.png, setting page.icon_url for plugin #{plugin['name']}"
        self.data['icon_url'] = icon_url
      end
    end

    def sanitize_readme(input, plugin)
        # Remove redundant headings with plugin's name
        readme = input.body.gsub('# ' + plugin['name'], '') \
        # Remove redundant descriptions that match existing
        .gsub(self.data['description'], '') \
        # Remove any remote images or badges from description
        .gsub(/\[?\!\[[\w\s?]+\]?\(.*\)/, '') \
        # Remove any whitespace from start or end of string
        .strip
        readme
    end

    def get_remote_file(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      response
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
        url = 'https://api.github.com/orgs/' + plugins_org + '/repos?page=' + page.to_s
        response = JSON.load(open(url, "Authorization" => "token " + token)) if !token.nil?
        response = JSON.load(open(url)) if token.nil? # TODO: Handle this better ^
        break if response.size == 0
        response.each { |h| repos << h }
        puts "Found #{response.size.to_s} more plugins to generate pages for"
        page += 1
      end

      repos = repos.select { |p| !p['language'].nil? }
      repos = repos.sort_by { |p| p['name'] }
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
      page.set_plugin_data(plugin, prev_plugin, next_plugin)
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
    end
  end

  # Jekyll hook - the generate method is called by Jekyll, and generates all of the plugin pages
  class PageGenerator < Generator
    safe true

    def generate(site)
      site.write_all_plugin_files
    end
  end
end
