require 'discourse_api'
require 'json'
require 'net/http'
require 'open-uri'
#require 'patreon'
require 'redcarpet'
require 'sanitize'

# TODO: Might be good to add some additional error handling and checks
# TODO: Check GitHub API calls for 403 code (rate limit excited or unauthorized)

module Jekyll
  # Define global variables
  $github_org = Jekyll.configuration({})['plugin_org'] || 'umods'
  $github_token = ENV['JEKYLL_GITHUB_TOKEN'] || ENV['GITHUB_TOKEN']
  $webhook_body = ENV['WEBHOOK_BODY']
  $file_exts = {
    'C#' => '.cs',
    'CoffeeScript' => '.coffee',
    'JavaScript' => '.js',
    'Lua' => '.lua',
    'Python' => '.py'
  }
  $discourse = DiscourseApi::Client
  $discourse_categories = []

  # Create a custom Markdown renderer for Redcarpet
  class CustomRenderer < Redcarpet::Render::XHTML
    # Set extensions for XHTML renderer
    def initialize(extensions = {}) # TODO: Figure out why these don't seem to be working
      super extensions.merge({
         escape_html: true,
         hard_wrap: true,
         safe_links_only: true,
         with_toc_data: true
      })
    end

    # Override default syntax highlighting to support Prism
    def block_code(code, language)
      %(
        <div class="code-highlight" data-label="">
          <span class="js-copy-to-clipboard copy-code">copy</span>
          <pre class="language-#{language}">
            <code class="js-code ghostIn language-#{language}">#{html_escape(code)}</code>
          </pre>
        </div>
      )
    end

    # Override default header styling
    def header(text, header_level)
      id = text.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')

      return %{<h#{header_level} id="#{id}">#{text}</h#{header_level}>} if header_level > 2

      %{
        <div class="separator"></div>
        <h#{header_level} id="#{id}">#{text}</h#{header_level}>
        <!-- #{id} -->
      }
    end

    # Escape code so that it doesn't affect the HTML
    def html_escape(string)
      string.gsub(/['&\"<>\/]/, {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
        '"' => '&quot;',
        "'" => '&#x27;',
        "/" => '&#x2F;',
      })
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
    # dest_name - The String name of the destination file
    # src_name - The String filename of the source page file, minus the markdown or html extension
    def initialize(site, base, dest_dir, dest_name, src_name)
      @site = site
      @base = base
      @dir = dest_dir
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

    # Fixes layout name being added to permalinks
    def url=(name)
      @url = name
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

      # Set the readme, if available
      url = "https://raw.githubusercontent.com/#{$github_org}/#{plugin['name']}/master/README.md"
      response = site.get_webrequest(url)
      if response.code == '200' && !response.body.nil?
        self.data['more_info'] = site.to_markdown(site.sanitize_readme(response.body, plugin))
        puts " - README.md found, set page.more_info"
      end
    end

    # Override so that we can control where the destination file goes
    def destination(dest)
      # The URL needs to be unescaped in order to preserve the correct filename
      File.join(dest, @dest_dir, @dest_name)
    end
  end

  # The Site class is a built-in Jekyll class with access to global site config information
  class Site
    # Cleans and removes any redundant text and formatting from a README.md file
    def sanitize_readme(input, plugin)
      # Remove redundant headings with repo's name
      input.gsub('# ' + plugin['name'], '') \
      # Remove any remote images or badges from description
        .gsub(/\[?!\[[\w\s?]+\]?\(.*\)/, '') \
      # Remove any whitespace from start or end of string
        .strip
    end

    # Cleans and remove any redundant text from a version number
    def sanitize_version(input)
      input.scan(/\d+/).join('.')
    end

    # Handles Markdown parsing and formatting
    def to_markdown(input)
      # Set extensions to use with renderer
      extensions = {
        autolink: true,
        fenced_code_blocks: true,
        lax_spacing: true,
        no_intra_emphasis: true,
        strikethrough: true,
        tables: true,
        underline: true
      }

      # Render and return input
      Redcarpet::Markdown.new(CustomRenderer, extensions).render(input)
    end

    # Send GET web request and return response
    def get_webrequest(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri.request_uri)
      http.request(request)
    end

    # Send PATCH web request and return response
    def patch_webrequest(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Patch.new(uri.request_uri)
      request.add_field('Authorization', "token #{$github_token}")
      request.body = body
      http.request(request)
    end

    # Gets topic information for a GitHub repository
    def get_repo_topics(repo)
      url = "https://api.github.com/repos/#{$github_org}/#{repo['name']}/topics"
      headers = {
        'Authorization' => "token #{$github_token}", # TODO: Make optional
        'Accept' => 'application/vnd.github.mercy-preview+json'
      }
      response = JSON.load(open(url, headers))
      # TODO: Check if response is valid?
      topics = response['names']
      puts " - Topics: #{topics.length}" if topics.length > 0
      topics
    end

    # Gets contributor information for a GitHub repository
    def get_repo_contributors(repo)
      contributors = []
      response = get_github_api(repo, 'contributors')
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
      response = get_github_api(repo, 'commits')
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
      response = get_github_api(repo, 'releases')
      response.each do |release|
        next if release['draft']
        releases << {
          'version' => sanitize_version(release['tag_name']),
          'author' => release['author']['login'],
          'prerelease' => release['prerelease'],
          'date' => release['published_at'],
          'changes' => release['body']
        }
        break if limit == 1
      end
      puts " - Releases: #{releases.length}" if releases.length > 0
      releases
    end

    # Gets content information for a GitHub repository
    def get_repo_contents(repo)
      contents = []
      response = get_github_api(repo, 'contents')
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

    # Gets an authenticated API response from GitHub
    def get_github_response(url)
      JSON.load(open(url, !$github_token.nil? && !$github_token.empty? ? {'Authorization' => "token #{$github_token}"} : nil))
    end

    #
    def get_github_api(repo, type)
      url = "https://api.github.com/repos/#{$github_org}/#{repo['name']}/#{type}"
      get_github_response(url)
    end

    # Gets all repository information for an organization using the GitHub API
    def get_org_repos(org, per_page = 100)
      puts "## Getting all repository information from GitHub"
      page = 1
      repos = []
      while true
        response = get_github_response("https://api.github.com/orgs/#{org}/repos?per_page=#{per_page}&page=#{page}")
        break if response.size == 0
        response.each {|h| repos << h}
        page += 1
      end
      repos
    end

    # Gets repository information for a single repository using the GitHub API
    def get_org_repo(org, repo_name)
      puts "## Getting repository information from GitHub"
      get_github_response("https://api.github.com/repos/#{org}/#{repo_name}")
    end

    # Creates a combined hash with specific repository information
    def create_repo_hash(repo)
      puts "## Getting information for #{repo['name']}"
      contents = get_repo_contents(repo)
      {
        'name' => repo['name'],
        'title' => repo['name'].humanize,
        'description' => Sanitize.clean(repo['description']).chomp('.'),
        'homepage' => repo['homepage'],
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

    # Creates instances of PluginPage, renders then, and writes the output to a file
    # Will create a page for the plugins index and each plugin
    def write_all_plugin_files
      plugins = {}

      # Check if WEBHOOK_BODY env is set
      if !$webhook_body.nil? || File.exist?('plugins.json')
        # Load existing plugins.json to check and add to
        json = JSON.load(open('https://umod.org/plugins.json'))
        # TODO: Make sure a response is valid, if json.size == 0
        json = JSON.load('plugins.json') if json.size == 0
        plugins = json['all']

        unless $webhook_body.nil?
          # Check WEBHOOK_BODY env to see what repo to rebuild
          webhook = JSON.parse($webhook_body)
          repo_name = webhook['repository']['name']

          # Check if webhook repo is already in plugins.json
          repo = get_org_repo($github_org, repo_name)
          plugins.delete_if {|id, _| id == repo['id']}
          plugins[repo['id']] = create_repo_hash(repo)
        end
      else
        # Get all GitHub repositories for organization
        repos = get_org_repos($github_org)

        # Only keep non-empty repository information and sort A-Z by name
        repos = repos.select {|repo| !repo['language'].nil?}.sort_by {|repo| repo['name']}
        puts "Non-empty repositories found: #{repos.size.to_s}"

        # Loop through remaining repositories
        repos.each do |repo|
          plugins[repo['id']] = create_repo_hash(repo)
        end
      end

      # Create an array of plugin IDs by topic
      topics = {}
      plugins.each do |key, plugin|
        plugin['topics'].each do |topic|
          unless topics.key?(topic)
            topics[topic] = []
          end
          topics[topic] << key.to_i
        end
      end

      # Create arrays of plugin IDs sorted
      sorted = {
        all: Hash[plugins.keys.map(&:to_i).zip(plugins.values)],
        sort_by: {
          title: plugins.sort_by {|_, plugin| plugin['title']}.map {|key, _| key.to_i}.uniq,
          last_updated: plugins.sort_by {|_, plugin| plugin['updated_at']}.map {|key, _| key.to_i}.reverse.uniq,
          newest: plugins.sort_by {|_, plugin| plugin['created_at']}.map {|key, _| key.to_i}.reverse.uniq,
          most_starred: plugins.sort_by {|_, plugin| plugin['stargazers']}.map {|key, _| key.to_i}.reverse.uniq,
          most_watched: plugins.sort_by {|_, plugin| plugin['watchers']}.map {|key, _| key.to_i}.reverse.uniq
        },
        topics: topics
      }

      # Setup connection to Discourse
      unless ENV['DISCOURSE_API_KEY'].nil?
        $discourse = DiscourseApi::Client.new(self.config['forums'])
        $discourse.api_key = ENV['DISCOURSE_API_KEY']
        $discourse.api_username = "system"
        $discourse.ssl(verify: false)
        $discourse_categories = $discourse.categories(parent_category_id: 21)
      end

      # Write Jekyll pages and individual plugin files
      write_plugins_index(plugins.values, '/')
      write_plugin_pages(plugins.values, 'plugins')

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
      # Write the plugins.html page
      index = PluginPage.new(self, self.source, dest_dir, 'plugins.html', 'plugins')
      index.url = '/plugins' # Fixes layout name being appended to permalink
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
            write_plugin_page(plugin, dest_dir, (index > 0) ? plugins[index - 1] : nil, plugins[index + 1])

            # Write the individual plugin's .json file
            write_static_file(plugin.to_json, "#{plugin['name']}.json", dest_dir)
          end
        else
          throw "No 'plugin' layout found."
        end
      end
    end

    # Write a plugins/plugin-name.html page
    def write_plugin_page(plugin, dest_dir, prev_plugin, next_plugin)
      puts "## Generating page for #{plugin['name']}"

      # Attach plugin data to global site variable. This allows pages to see this plugin's data
      page = PluginPage.new(self, self.source, dest_dir, "#{plugin['name']}.html", 'plugin')
      page.set_page_data(plugin, prev_plugin, next_plugin)
      page.url = "/plugins/#{plugin['name'].downcase}" # Fixes layout name being appended to permalinks
      page.render(self.layouts, site_payload)
      page.write(self.dest)
      self.pages << page

      # Download the plugin file to serve directly
      if !plugin['download_url'].nil? && !plugin['private']
        filename = plugin['name'] + $file_exts[plugin['language']]
        download = open(plugin['download_url']) {|f| f.read}
        unless download.nil?
          write_static_file(download, filename, dest_dir)
          puts " - Downloaded file #{filename}"
        end
      end

      update_repo_homepage(plugin)
      create_forums_category(plugin) unless ENV['DISCOURSE_API_KEY'].nil?
    end

    # Update homepage in plugin's repository
    def update_repo_homepage(plugin)
      new_homepage = "#{self.config['home']}/plugins/#{plugin['name'].downcase}"

      body = {
        'name' => plugin['name'],
        'homepage' => new_homepage,
        'private' => plugin['private'],
        'has_issues' => true,
        'has_projects' => true,
        'has_wiki' => false
      }
      repo_url = "https://api.github.com/repos/#{$github_org}/#{plugin['name']}"
      patch_webrequest(repo_url, body.to_json) if plugin['homepage'] != new_homepage
    end

    # Create Discourse forums category for plugin
    def create_forums_category(plugin)
      # Check if category exists before attempting to create
      $discourse_categories.each do |category|
        return if category['name'] == plugin['title']
      end

      # Create new forum category for plugin
      new_category = $discourse.create_category(
        name: plugin['title'],
        color: "25AAE2",
        text_color: "FFFFFF",
        parent_category_id: 21, # Plugin Support category
        description: "Support and discussion for #{plugin['name']}. Visit the plugin's page at #{self.config['home']}/plugins/#{plugin['name']}." # Not working with Discourse yet
      )
      puts " - Created Discourse category: #{new_category['name']}"
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
