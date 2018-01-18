#require 'discourse_api'
require 'json'
require 'net/http'
require 'open-uri'
#require 'patreon'
require 'redcarpet'
require 'sanitize'

# TODO: Check if from Netlify and use WEBHOOK_BODY env to see what content to change
# TODO: Might be good to add some additional error handling and checks
# TODO: Check GitHub API calls for 403 code (rate limit excited or unauthorized)

module Jekyll
  # Create a custom Markdown renderer for Redcarpet
  class CustomRender < Redcarpet::Render::XHTML
    def block_code(code, language)
      %(<div class="tabs js-tabs code-highlight-tabs">
        <div class="tab-content">
          <div class="code-highlight" data-label="">
            <span class="js-copy-to-clipboard copy-code">copy</span>
            <pre class="language-#{language}">
              <code class="js-code ghostIn language-#{language}">
#{code}
              </code>
            </pre>
          </div>
        </div>
      </div>)
    end
  end

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
      puts " - Plugin title set to: #{plugin['title']}"

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
    # Define global variables
    $token = ENV['JEKYLL_GITHUB_TOKEN'] || ENV['GITHUB_TOKEN']
    $plugins_org = Jekyll.configuration({})['plugin_org'] || 'umods'
    $plugins_dir = 'plugins'
    $file_exts = {
      'C#' => '.cs',
      'CoffeeScript' => '.coffee',
      'JavaScript' => '.js',
      'Lua' => '.lua',
      'Python' => '.py'
    }

    # Cleans and removes any redundant text and formatting from a README.md file
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

    # Cleans and remove any redundant text from a version number
    def sanitize_version(input)
      version = input.scan(/\d+/).join('.')
      version
    end

    # Gets the response code and body for a remote file
    def get_remote_file(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      response
    end

    # Gets topic information for a GitHub repository
    def get_repo_topics(repo)
      url = 'https://api.github.com/repos/' + $plugins_org + '/' + repo['name'] + '/topics'
      headers = {
        'Authorization' => 'token ' + $token, # TODO: Make optional
        'Accept' => 'application/vnd.github.mercy-preview+json'
      }
      response = JSON.load(open(url, headers))
      topics = response['names']
      puts " - Topics: #{topics.length}" if topics.length > 0
      topics
    end

    # Gets contributor information for a GitHub repository
    def get_repo_contributors(repo)
      contributors = []
      url = 'https://api.github.com/repos/' + $plugins_org + '/' + repo['name'] + '/contributors'
      response = JSON.load(open(url, !$token.nil? && !$token.empty? ? {"Authorization" => "token " + $token} : nil))
      response.each do |contributor|
        contributors << {
          'name' => contributor['login'],
          'avatar_url' => contributor['avatar_url'],
          'contributions' => contributor['contributions']
        }
      end
      puts " - Contributors: #{contributors.length}" if contributors.length > 0
      contributors
    end

    # Gets commit information for a GitHub repository
    def get_repo_commits(repo, limit)
      commits = []
      url = 'https://api.github.com/repos/' + $plugins_org + '/' + repo['name'] + '/commits'
      response = JSON.load(open(url, !$token.nil? && !$token.empty? ? {"Authorization" => "token " + $token} : nil))
      response.each do |commit|
        commits << {
          'sha' => commit['sha'],
          'date' => commit['commit']['author']['date'],
        }
        break if limit == 1
      end
      puts " - Commits: #{commits.length}" if commits.length > 0
      commits
    end

    # Gets release information for a GitHub repository
    def get_repo_releases(repo, limit)
      releases = []
      url = 'https://api.github.com/repos/' + $plugins_org + '/' + repo['name'] + '/releases'
      response = JSON.load(open(url, !$token.nil? && !$token.empty? ? {"Authorization" => "token " + $token} : nil))
      response.each do |release|
        next if release['draft']
        releases << {
          'version' => sanitize_version(release['tag_name']),
          'author' => release['author']['login'],
          'prerelease' => release['prerelease'],
          'date' => release['published_at'],
          'changes' => release['body']
        }
      end
      puts " - Releases: #{releases.length}" if releases.length > 0
      releases
    end

    # Gets content information for a GitHub repository
    def get_repo_contents(repo)
      contents = []
      url = 'https://api.github.com/repos/' + $plugins_org + '/' + repo['name'] + '/contents'
      response = JSON.load(open(url, !$token.nil? && !$token.empty? ? {"Authorization" => "token " + $token} : nil))
      response.each do |content|
        contents << {
          'filename' => content['name'],
          'sha' => content['sha'],
          'size' => content['size'],
          'download_url' => content['download_url']
        }
      end
      puts " - Contents: #{contents.length}" if contents.length > 0
      contents
    end

    # Gets the URL for a specific file from a GitHub repository
    def get_contents_url(contents, filename)
      contents.each do |content|
        return content['download_url'] if content['filename'] == filename
      end
      nil
    end

    # Creates instances of PluginPage, renders then, and writes the output to a file
    # Will create a page for the plugins index and each plugin
    def write_all_plugin_files
      # Checks GitHub API for repository information and converts it to a custom format
      puts "Getting repository information from GitHub"
      page = 1
      repos = []
      while true
        url = 'https://api.github.com/orgs/' + $plugins_org + '/repos?per_page=100&page=' + page.to_s
        response = JSON.load(open(url, !$token.nil? && !$token.empty? ? {"Authorization" => "token " + $token} : nil))
        break if response.size == 0
        response.each{|h| repos << h}
        page += 1
      end

      # Only keep non-empty repository information
      repos = repos.select{|p| !p['language'].nil?}

      # Sort repository information A-Z by name
      repos = repos.sort_by{|p| p['name']}

      puts "Non-empty repositories found: #{repos.size.to_s}"

      # Loop through remaining repository information and store
      plugins = []
      repos.each do |repo|
        puts
        puts "## Getting information for #{repo['name']}"
        contents = get_repo_contents(repo)
        plugins << {
          'id' => repo['id'],
          'name' => repo['name'],
          'title' => repo['name'].humanize,
          'description' => Sanitize.clean(repo['description']).chomp('.'),
          'language' => repo['language'],
          'topics' => get_repo_topics(repo),
          'created_at' => repo['created_at'],
          'updated_at' => repo['pushed_at'],
          'github_url' => repo['html_url'],
          'icon_url' => get_contents_url(contents, 'icon.png'),
          'download_url' => get_contents_url(contents, repo['name'] + $file_exts[repo['language']]),
          'private' => repo['private'],
          'stargazers' => repo['stargazers_count'],
          'watchers' => repo['watchers_count'],
          'license_id' => !repo['license'].nil? ? repo['license']['spdx_id'] : nil,
          'license_name' => !repo['license'].nil? ? repo['license']['name'] : nil,
          'contributors' => get_repo_contributors(repo),
          'latest_commit' => get_repo_commits(repo, 1).first,
          'latest_release' => get_repo_releases(repo, 1).first,
        }
      end

      # Write Jekyll pages and individual plugin files
      write_plugins_index(plugins, $plugins_dir)
      write_plugin_pages(plugins, $plugins_dir)

      # Create an array of plugin IDs by topic
      topics = {}
      plugins.each do |plugin|
        plugin['topics'].each do |topic|
          if !topics.key?(topic)
            topics[topic] = []
          end
          topics[topic] << plugin['id']
        end
      end

      # Create arrays of plugins IDs sorted
      sorted = {
        'all' => plugins,
        'sort_by' => {
          'title'        => plugins.sort_by{|p| p['title']}.map{|p| p['id']},
          'last_updated' => plugins.sort_by{|p| p['updated_at']}.reverse.map{|p| p['id']},
          'newest'       => plugins.sort_by{|p| p['created_at']}.reverse.map{|p| p['id']},
          'most_starred' => plugins.sort_by{|p| p['stargazers']}.reverse.map{|p| p['id']},
          'most_watched' => plugins.sort_by{|p| p['watchers']}.reverse.map{|p| p['id']}
        },
        'topics' => topics
      }

      # Write the plugins.json file
      write_static_file(sorted.to_json, 'plugins.json', '/')
    end

    # Write a static file to specified directory under _site
    def write_static_file(contents, filename, dest_dir)
        unless File.directory?(File.join(self.source, dest_dir))
          FileUtils.mkdir_p(File.join(self.source, dest_dir))
        end
        File.write(File.join(self.source, File.join(dest_dir, filename)), contents)
        self.static_files << StaticFile.new(self, self.source, dest_dir, filename)
    end

    # Write the plugins index files
    def write_plugins_index(plugins, dest_dir)
      # Write the plugins/index.html page
      index = PluginPage.new(self, self.source, dest_dir, 'index.html', 'plugins')
      index.set_data('plugins', plugins)
      index.render(self.layouts, site_payload)
      index.write(self.dest)
      self.pages << index
    end

    # Loops through the list of plugin and processes each one
    def write_plugin_pages(plugins, dest_dir)
      if plugins && plugins.length > 0
        if self.layouts.key? 'plugin'
          plugins.each_with_index do |plugin, index|
            # Write the individual plugin's page
            write_plugin_page(plugin, dest_dir, (index > 0) ? plugins[index-1] : nil, plugins[index+1])

            # Write the individual plugin's .json file
            write_static_file(plugin.to_json, plugin['name'] + '.json', dest_dir)
          end
        else
          throw "No 'plugin' layout found."
        end
      end
    end

    # Write a plugins/plugin-name/index.html page
    def write_plugin_page(plugin, dest_dir, prev_plugin, next_plugin)
      puts
      puts "## Generating page for #{plugin['name']}"

      # Set the readme variable, if available
      url = 'https://raw.githubusercontent.com/' + $plugins_org + '/' + plugin['name'] + '/master/README.md'
      response = get_remote_file(url)
      if response.code == '200' && !response.body.nil?
        extensions = {autolink: true, fenced_code_blocks: true, lax_spacing: true, no_intra_emphasis: true, strikethrough: true, tables: true, underline: true, filter_html: true, hard_wrap: true, no_images: true, no_styles: true, safe_links_only: true, with_toc_data: true}
        markdown = Redcarpet::Markdown.new(CustomRender, extensions)
        plugin['readme'] = markdown.render(response.body)
        puts " - README.md found, set plugin.readme variable"
      end

      # Attach plugin data to global site variable. This allows pages to see this plugin's data
      page = PluginPage.new(self, self.source, File.join(dest_dir, plugin['name']), 'index.html', 'plugin')
      page.set_page_data(plugin, prev_plugin, next_plugin)
      page.render(self.layouts, site_payload)
      page.write(self.dest)
      self.pages << page

      # Download the plugin file to serve directly
      if !plugin['download_url'].nil? && !plugin['private']
        filename = plugin['name'] + $file_exts[plugin['language']]
        download = open(plugin['download_url']) {|f| f.read}
        if !download.nil?
          write_static_file(download, filename, File.join(File.join(dest_dir, plugin['name'])))
          puts " - Downloaded #{filename} from GitHub"
        end
      end

      #create_forums_category(plugin)
    end

=begin
    def create_forums_category(plugin)
      discourse = DiscourseApi::Client.new(Jekyll.configuration({})['forums'])
      discourse.api_key = ENV['DISCOURSE_API_KEY']
      discourse.api_username = "system"
      discourse.ssl(verify: false)

      plugin_name = plugin['name'].humanize

      # TODO: Check if category exists before attempting to create
      #categories = JSON.parse(discourse.categories(parent_category_id: 21))
      #if !categories['name'].to_a.detect{|e| e['name'] == plugin_name}.nil? # TODO: Fix this code and check
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
        description: "Support and discussion for #{plugin['name']}. Visit the plugin's page at #{Jekyll.configuration({})['url']}/plugins/#{plugin['name']}/."
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
