# 
# This a modified version of data_page_generator.rb by Adolfo Villafiorita.
#
# Generate pages from individual records in yml files
# (c) 2014-2016 Adolfo Villafiorita
#
# Additions and modifications (c) 2016 Tim Sherratt (@wragge)
# Distributed under the conditions of the MIT License


module Jekyll

  # this class is used to tell Jekyll to generate a page
  class DataPage < Page

    # - site and base are copied from other plugins: to be honest, I am not sure what they do
    #
    # - `index_files` specifies if we want to generate named folders (true) or not (false)
    # - `dir` is the default output directory
    # - `data` is the data defined in `_data.yml` of the record for which we are generating a page
    # - `name` is the key in `data` which determines the output filename
    # - `template` is the name of the template for generating the page
    # - `extension` is the extension for the generated file

    def initialize(site, base, index_files, dir, data, name, template, extension)
      @site = site
      @base = base

      # @dir is the directory where we want to output the page
      # @name is the name of the page to generate
      #
      # the value of these variables changes according to whether we
      # want to generate named folders or not

      filename = Utils.slugify(data[name])
      if index_files
        @dir = dir + (index_files ? "/" + filename + "/" : "")
        @name =  "index" + "." + extension.to_s
      else
        @dir = dir
        @name = filename + "." + extension.to_s
      end

      self.process(@name)
      self.read_yaml(File.join(base, '_layouts'), template + ".html")
      self.data['title'] = data[name]
      # add all the information defined in _data for the current record to the
      # current page (so that we can access it with liquid tags)
      self.data.merge!(data)
    end
  end

  class DataPagesGenerator < Generator
    safe true

    # generate loops over _config.yml/page_gen invoking the DataPage
    # constructor for each record for which we want to generate a page

    def generate(site)

      # page_gen_dirs determines whether we want to generate index pages
      # (name/index.html) or standard files (name.html). This information
      # is passed to the DataPage constructor, which sets the @dir variable
      # as required by this directive

      index_files = site.config['page_gen-dirs'] == true

      # data contains the specification of the data for which we want to generate
      # the pages (look at the README file for its specification)
      data = site.config['page_gen']
      types = site.config['data_types']
      if data
        data.each do |data_spec|
          # template = data_spec['template'] || data_spec['data']
          name = data_spec['name']
          # dir = data_spec['dir'] || data_spec['data']
          # Added 2 lines: Set context and type for JSON-LD 
          context = data_spec['context'] || "http://schema.org/"
          # type = data_spec['type'] || "Thing"
          extension = data_spec['extension'] || "html"

          # records is the list of records defined in _data.yml
          # for which we want to generate different pages
          records = nil
          data_spec['data'].split('.').each do |level|
            if records.nil?
              records = site.data[level]
            else
              records = records[level]
            end
          end
          records.each do |record|
            # Added 3 lines: Add context and type for JSON-LD to each record
            collection = record["collection"]
            dir = types[collection]["dir"] || collection
            template = types[collection]["template"]
            type = types[collection]["type"]
            record["@context"] = context
            record["data"]["@type"] = type
            record["data"]["name"] = record["name"]
            site.pages << DataPage.new(site, site.source, index_files, dir, record, name, template, extension)
          end
        end
      end
    end
  end

  module DataPageLinkGenerator

    # use it like this: {{input | datapage_url: dir}}
    # to generate a link to a data_page.
    #
    # the filter is smart enough to generate different link styles
    # according to the data_page-dirs directive ...
    #
    # ... however, the filter is not smart enough to support different
    # extensions for filenames.
    #
    # Thus, if you use the `extension` feature of this plugin, you
    # need to generate the links by hand

    def datapage_url(input, dir)
      @gen_dir = Jekyll.configuration({})['page_gen-dirs']
      @baseurl = Jekyll.configuration({})['baseurl']
      if @gen_dir then
        # Modified to make relative to baseurl
        @baseurl + "/" + dir + "/" + Utils.slugify(input) + "/index.html"
      else
        @baseurl + "/" + dir + "/" + Utils.slugify(input) + ".html"
      end
    end
  end

  module LODLinkGenerator

    # This generates an 'a' tag & link that points to the entity identified by the supplied name and collection.
    # It uses RDFa to relate the text to the identifier in the href attribute. 
    # For convenience it also saves the original name and collection values as data attributes for JS stuff.
    # So for example:
    # {{ "James Minahan" | lod_link: "", "people" }}
    # produces
    # <a data-name="James Minahan" data-collection="people" property="name" href="/ed/people/james-minahan/">James Minahan</a>
    # While
    # {{ "James" | lod_link: "James Minahan", "people" }}
    # produces
    # <a data-name="James Minahan" data-collection="people" property="name" href="/ed/people/james-minahan/">James</a>

    def lod_link(input, name)
      site_url = @context.registers[:site].config['url']
      base_url = @context.registers[:site].config['baseurl']
      if name == ""
        name = input
      end
      data = @context.registers[:site].data['data']
      collection = nil
      data.each do |record|
        if name == record["name"]
          
          collection = record["collection"]
          break
        end
      end
      if collection
        url = "#{base_url}/#{collection}/#{Utils.slugify(name)}/"
        "<a data-name=\"#{name}\" data-collection=\"#{collection}\" property=\"name\" href=\"#{url}\">#{input}</a>"
      else
        puts "Not found: #{name}"
        "#{input}"
      end
    end
  end

  module LODUrlGenerator

    # Formats a complete URI when supplied with a name and collection.
    # Use in lists etc. For example:
    #{% for knows in page.data.knows %}
      #<li><a href="{{ knows.name | lod_url: "", knows.collection }}">{{ knows.name }}</a></li>
    #{% endfor %}

    def lod_url(name, collection)
      site_url = @context.registers[:site].config['url']
      base_url = @context.registers[:site].config['baseurl']
      "#{site_url}#{base_url}/#{collection}/#{Utils.slugify(name)}/"
    end
  end

  module JSONLDGenerator
    require 'yaml'
    require 'json'

    include LODUrlGenerator

    # Creates JSON-LD about an entity for embedding in a page.
    # Converts 'name' & 'collection' pairs to '@id's.
    # Wraps the JSON-LD in script tags.
    #
    # Feed it a page and get back JSON-LD wrapped in a script tag -- eg: {{ page | jsonldify }}

    def jsonldify(page)
      site_url = @context.registers[:site].config['url']
      base_url = @context.registers[:site].config['baseurl']
      data = page["data"]
      context = page["@context"]
      data.each do |key, value|
        if value.kind_of?(Hash)
          if value.has_key?("name") and value.has_key?("collection")
            data[key] = {"@id": lod_url(value["name"], value["collection"])}
          end
        elsif value.kind_of?(Array)
          urls = []
          value.each do |svalue|
            if svalue.has_key?("name") and svalue.has_key?("collection")
              urls.push({"@id": lod_url(svalue["name"], svalue["collection"])})
            else
              urls.push(svalue)
            end
          end
          if !urls.empty?
             data[key] = urls
          end
        end
      end
      page_url = "#{site_url}#{base_url}#{page["url"]}"
      data["@id"] = page_url
      graph = []
      graph.push(data)
      graph.push({"@id": "#{page_url}index.html", "@type": "http://schema.org/WebPage", "mainEntity": {"@id": page_url}})
      lod = {"@context": context, "@graph": graph}
      return "<script type=\"application/ld+json\">#{JSON.generate(lod)}</script>"
    end
  end

  module LODMentionsGenerator
    require 'nokogiri'
    require 'json'

    # This creates JSON-LD that decribes any entities (people, places etc) mentioned in a text.
    # The returned JSON-LD can be embedded in a page for Linked Data harvesting and discovery.
    #
    # Feed it a page and get back JSON-LD wrapped in a script tag -- eg: {{ page | lod_mentions}}

    def lod_mentions(page)
      site_url = @context.registers[:site].config['url']
      base_url = @context.registers[:site].config['baseurl']
      mentions = []
      lod = {'@context': 'http://schema.org', '@id': page['url']}
      html = Nokogiri::HTML(page['content'])
      html.css("a[property=name]").each do |link|
        mentions.push({'@id': "#{site_url}#{link['href']}"})
      end
      lod['mentions'] = mentions
      return "<script type=\"application/ld+json\">#{JSON.generate(lod)}</script>"
    end
  end

  module LODReferencesGenerator
    require 'nokogiri'
    require 'json'

    # Creates JSON that links paragraphs (by numeric id) with LOD references within that para.
    # This can be saved in a page and then used later by whizz-bag JS inerface-y stuff.
    # 
    # Feed it a page and get back JSON -- eg: <script>var references = {{ page | lod_references }};</script>

    def lod_references(page)
      site_url = @context.registers[:site].config['url']
      base_url = @context.registers[:site].config['baseurl']
      references = {}
      lod = {'@context': 'http://schema.org', '@id': page['url']}
      html = Nokogiri::HTML(page['content'])
      links = {}
      html.css("p").each do |para|
        para.css("a[property=name]").each do |link|
          links[link.content] = {'url': link['href'], 'name': link['data-name'], 'collection': link['data-collection']}
          #link.replace(link.content)
        end
      end
      labels = links.keys.sort_by(&:length).reverse!
      html.css("p").each do |para|
        labels.each do |label|
          if para.inner_html =~ /\b#{label}\b/
            details = links[label]
            link = lod_link(label, details[:name])
            para.inner_html = para.inner_html.gsub(/(?<!\>)(?<!\=")\b#{label}\b(?!\<)(?!\")/, link)
          end
        end
      end
      html.css("p").each_with_index do |para, index|
        para_refs = []
        para.css("a[property=name]").each do |link|
          entity = {'url': link['href'], 'name': link['data-name'], 'collection': link['data-collection']}
          if not para_refs.include? entity
            para_refs.push(entity)
          end
        end
        if !para_refs.empty?
          references["para-#{index}"] = para_refs
        end
      end
      return JSON.generate(references)
    end
  end

  module LODIdsGenerator
    require 'nokogiri'

    #
    # Adds numeric ids to ps and blockquotes, so they can be referenced in JS interface-y stuff.
    # Use it on content in page templates -- eg: {{ content | lod_ids }}
    #

    def lod_ids(content)
      html = Nokogiri::HTML(content)
      html.css("p").each_with_index do |para, index|
        para['id'] = "para-#{index}"
      end
      html.css("blockquote").each_with_index do |quote, index|
        quote['id'] = "quote-#{index}"
      end
      return html.to_html
    end
  end

  module LODLabelsGenerator
    require 'nokogiri'
    include LODLinkGenerator

    def lod_labels(content)
      html = Nokogiri::HTML(content)
      references = {}
      html.css("p").each do |para|
        para.css("a[property=name]").each do |link|
          references[link.content] = {'url': link['href'], 'name': link['data-name'], 'collection': link['data-collection']}
          #link.replace(link.content)
        end
      end
      labels = references.keys.sort_by(&:length).reverse!
      html.css("p").each do |para|
        labels.each do |label|
          if para.inner_html =~ /\b#{label}\b/
            details = references[label]
            link = lod_link(label, details[:name])
            para.inner_html = para.inner_html.gsub(/(?<!\>)(?<!\=")\b#{label}\b(?!\<)(?!")/, link)
          end
        end
      end
      return html.to_html
    end
  end
end

Liquid::Template.register_filter(Jekyll::DataPageLinkGenerator)
Liquid::Template.register_filter(Jekyll::LODLinkGenerator)
Liquid::Template.register_filter(Jekyll::LODUrlGenerator)
Liquid::Template.register_filter(Jekyll::JSONLDGenerator)
Liquid::Template.register_filter(Jekyll::LODMentionsGenerator)
Liquid::Template.register_filter(Jekyll::LODReferencesGenerator)
Liquid::Template.register_filter(Jekyll::LODIdsGenerator)
Liquid::Template.register_filter(Jekyll::LODLabelsGenerator)
