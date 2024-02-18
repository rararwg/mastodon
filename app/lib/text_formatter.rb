# frozen_string_literal: true

require_relative 'tex2ml'

class TextFormatter
  include ActionView::Helpers::TextHelper
  include ERB::Util
  include RoutingHelper

  URL_PREFIX_REGEX = /\A(https?:\/\/(www\.)?|xmpp:)/.freeze

  DEFAULT_REL = %w(nofollow noopener noreferrer).freeze

  DEFAULT_OPTIONS = {
    multiline: true,
  }.freeze

  attr_reader :text, :options

  class HTMLRenderer < Redcarpet::Render::HTML
    def initialize(options, &block)
      super(options)
      @format_link = block
    end

    def block_code(code, _language)
      <<~HTML.squish
        <pre><code>#{h(code).gsub("\n", '<br/>')}</code></pre>
      HTML
    end

    def autolink(link, link_type)
      return link if link_type == :email
      @format_link.call(link)
    end
  end


  # @param [String] text
  # @param [Hash] options
  # @option options [Boolean] :multiline
  # @option options [Boolean] :with_domains
  # @option options [Boolean] :with_rel_me
  # @option options [Array<Account>] :preloaded_accounts
  def initialize(text, options = {})
    @options = DEFAULT_OPTIONS.merge(options)
    @text    = format_markdown(text)
  end

  # Differs from official `TextFormatter` by skipping HTML tags and entities
  def entities
    @entities ||= begin
      gaps = []
      total_offset = 0

      escaped = text.gsub(/<[^>]*>|&#[0-9]+;/) do |match|
        total_offset += match.length - 1
        end_offset = Regexp.last_match.end(0)
        gaps << [end_offset - total_offset, total_offset]
        ' '
      end

      Extractor.extract_entities_with_indices(escaped, extract_url_without_protocol: false).map do |entity|
        start_pos, end_pos = entity[:indices]
        offset_idx = gaps.rindex { |gap| gap.first <= start_pos }
        offset = offset_idx.nil? ? 0 : gaps[offset_idx].last
        entity.merge(indices: [start_pos + offset, end_pos + offset])
      end
    end
  end

  # Differs from official TextFormatter by not messing with newline after parsing
  def to_s
    return ''.html_safe if text.blank?

    html = rewrite do |entity|
      if entity[:url]
        link_to_url(entity)
      elsif entity[:hashtag]
        link_to_hashtag(entity)
      elsif entity[:screen_name]
        link_to_mention(entity)
      end
    end

    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  class << self
    include ERB::Util

    def shortened_link(url, rel_me: false)
      url = Addressable::URI.parse(url).to_s
      rel = rel_me ? (DEFAULT_REL + %w(me)) : DEFAULT_REL

      prefix      = url.match(URL_PREFIX_REGEX).to_s
      display_url = url[prefix.length, 30]
      suffix      = url[prefix.length + 30..-1]
      cutoff      = url[prefix.length..-1].length > 30

      <<~HTML.squish.html_safe # rubocop:disable Rails/OutputSafety
        <a href="#{h(url)}" target="_blank" rel="#{rel.join(' ')}"><span class="invisible">#{h(prefix)}</span><span class="#{cutoff ? 'ellipsis' : ''}">#{h(display_url)}</span><span class="invisible">#{h(suffix)}</span></a>
      HTML
    rescue Addressable::URI::InvalidURIError, IDN::Idna::IdnaError
      h(url)
    end
  end

  private

  # Differs from official `TextFormatter` in that it keeps HTML; but it sanitizes at the end to remain safe
  def rewrite
    entities.sort_by! do |entity|
      entity[:indices].first
    end

    result = ''.dup

    last_index = entities.reduce(0) do |index, entity|
      indices = entity[:indices]
      result << text[index...indices.first]
      result << yield(entity)
      indices.last
    end

    result << text[last_index..-1]

    Sanitize.fragment(result, Sanitize::Config::MASTODON_OUTGOING)
  end

  def format_markdown(html)
    html = markdown_formatter.render(html)
    html.delete("\r").delete("\n")
  end

  def format_latex(html)
    Tex2ml.render(html)
  end

  def markdown_formatter
    extensions = {
      autolink: true,
      no_intra_emphasis: true,
      fenced_code_blocks: true,
      disable_indented_code_blocks: true,
      strikethrough: true,
      lax_spacing: true,
      space_after_headers: true,
      superscript: true,
      underline: true,
      highlight: true,
      footnotes: false,
    }

    renderer = HTMLRenderer.new({
      filter_html: false,
      escape_html: false,
      no_images: true,
      no_styles: true,
      safe_links_only: true,
      hard_wrap: true,
      link_attributes: { target: '_blank', rel: 'nofollow noopener' },
    }) do |url|
      link_to_url({ url: url })
    end

    Redcarpet::Markdown.new(renderer, extensions)
  end

  def link_to_url(entity)
    TextFormatter.shortened_link(entity[:url], rel_me: with_rel_me?)
  end

  def link_to_hashtag(entity)
    hashtag = entity[:hashtag]
    url     = tag_url(hashtag)

    <<~HTML.squish
      <a href="#{h(url)}" class="mention hashtag" rel="tag">#<span>#{h(hashtag)}</span></a>
    HTML
  end

  def link_to_mention(entity)
    username, domain = entity[:screen_name].split('@')
    domain           = nil if local_domain?(domain)
    account          = nil

    if preloaded_accounts?
      same_username_hits = 0

      preloaded_accounts.each do |other_account|
        same_username = other_account.username.casecmp(username).zero?
        same_domain   = other_account.domain.nil? ? domain.nil? : other_account.domain.casecmp(domain)&.zero?

        if same_username && !same_domain
          same_username_hits += 1
        elsif same_username && same_domain
          account = other_account
        end
      end
    else
      account = entity_cache.mention(username, domain)
    end

    return "@#{h(entity[:screen_name])}" if account.nil?

    url = ActivityPub::TagManager.instance.url_for(account)
    display_username = same_username_hits&.positive? || with_domains? ? account.pretty_acct : account.username

    <<~HTML.squish
      <span class="h-card"><a href="#{h(url)}" class="u-url mention">@<span>#{h(display_username)}</span></a></span>
    HTML
  end

  def entity_cache
    @entity_cache ||= EntityCache.instance
  end

  def tag_manager
    @tag_manager ||= TagManager.instance
  end

  delegate :local_domain?, to: :tag_manager

  def multiline?
    options[:multiline]
  end

  def with_domains?
    options[:with_domains]
  end

  def with_rel_me?
    options[:with_rel_me]
  end

  def preloaded_accounts
    options[:preloaded_accounts]
  end

  def preloaded_accounts?
    preloaded_accounts.present?
  end
end
