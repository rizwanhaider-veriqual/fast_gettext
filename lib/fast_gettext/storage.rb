module FastGettext
  # Responsibility:
  #  - store data threadsave
  #  - provide error messages when repositories are unconfigured
  #  - accept/reject locales that are set by the user
  module Storage
    class NoTextDomainConfigured < RuntimeError
      def to_s
        "Current textdomain (#{FastGettext.text_domain.inspect}) was not added, use FastGettext.add_text_domain !"
      end
    end

    [:available_locales, :_locale, :text_domain, :pluralisation_rule, :_ext1, :_ext2].each do |method_name|
      key = "fast_gettext_#{method_name}".to_sym
      define_method "#{method_name}=" do |value|
        Thread.current[key]=value
        update_current_cache
      end
    end

    def _locale
      Thread.current[:fast_gettext__locale]
    end
    private :_locale, :_locale=

    def _ext1
      Thread.current[:fast_gettext__ext1]
    end
    private :_ext1, :_ext1=

    def _ext2
      Thread.current[:fast_gettext__ext2]
    end
    private :_ext2, :_ext2=


    def available_locales
      locales = Thread.current[:fast_gettext_available_locales] || default_available_locales
      return unless locales
      locales.map{|s|s.to_s}
    end

    # == cattr_accessor :default_available_locales
    @@default_available_locales = nil
    def default_available_locales=(avail_locales)
      @@default_available_locales = avail_locales
      update_current_cache
    end

    def default_available_locales
      @@default_available_locales
    end


    def text_domain
      Thread.current[:fast_gettext_text_domain] || default_text_domain
    end

    # == cattr_accessor :default_text_domain
    @@default_text_domain = nil
    def default_text_domain=(domain)
      @@default_text_domain = domain
      update_current_cache
    end

    def default_text_domain
      @@default_text_domain
    end


    # if overwritten by user( FastGettext.pluralisation_rule = xxx) use it,
    # otherwise fall back to repo or to default lambda
    def pluralisation_rule
      Thread.current[:fast_gettext_pluralisation_rule] ||  current_repository.pluralisation_rule || lambda{|i| i!=1}
    end

    def current_cache
      Thread.current[:fast_gettext_current_cache] || {}
    end

    def current_cache=(cache)
      Thread.current[:fast_gettext_current_cache] = cache
    end

    def current_ext1
      Thread.current[:fast_gettext_current_ext1] || {}
    end

    def current_ext1=(cache)
      Thread.current[:fast_gettext_current_ext1] = cache
    end

    def current_ext2
      Thread.current[:fast_gettext_current_ext2] || {}
    end

    def current_ext2=(cache)
      Thread.current[:fast_gettext_current_ext2] = cache
    end

    #global, since re-parsing whole folders takes too much time...
    @@translation_repositories={}
    def translation_repositories
      @@translation_repositories
    end

    # used to speedup simple translations, does not work for pluralisation
    # caches[text_domain][locale][key]=translation
    @@caches={}
    def caches
      @@caches
    end

    def current_repository
      translation_repositories[text_domain] || raise(NoTextDomainConfigured)
    end

    def key_exist?(key)
      !!(cached_find key)
    end

    def cached_find(key)
      # check we ahve the cache set if the cache is empty
      update_current_cache if current_cache.size == 0

      translation = current_cache[key]
      translation = current_ext2[key] if ext2
      translation ||= current_ext1[key] if ext1

      translation ||= current_cache[key]
      if translation.nil? # uncached
        current_cache[key] = current_repository[key] || false
        current_cache[key]
      else
        translation
      end
    end

    def cached_plural_find(*keys)
      key = '||||' + keys * '||||'
      translation = current_cache[key]
      if translation.nil? # uncached
        current_cache[key] = current_repository.plural(*keys) || false
      else
        translation
      end
    end

    def expire_cache_for(key)
      current_cache.delete(key)
    end

    def locale
      _locale || ( default_locale || (available_locales||[]).first || 'en' )
    end
    
    def ext1
      _ext1 
    end

    def ext2
      _ext2
    end
    
    def ext1=(new_ext)
      self._ext1 = new_ext
    end

    def ext2=(new_ext)
      self._ext2 = new_ext
    end

    def set_ext1(new_locale)
      self.ext1 = new_locale
      locale
    end
    
    def set_ext2(new_locale)
      self.ext2 = new_locale
      locale
    end
    
    def locale=(new_locale)
      new_locale = best_locale_in(new_locale)
      self._locale = new_locale if new_locale
    end

    # for chaining: puts set_locale('xx') == 'xx' ? 'applied' : 'rejected'
    # returns the current locale, not the one that was supplied
    # like locale=(), whoes behavior cannot be changed
    def set_locale(new_locale)
      self.locale = new_locale
      locale
    end

    @@default_locale = nil
    def default_locale=(new_locale)
      @@default_locale = best_locale_in(new_locale)
      update_current_cache
    end

    def default_locale
      @@default_locale
    end

    #Opera: de-DE,de;q=0.9,en;q=0.8
    #Firefox de-de,de;q=0.8,en-us;q=0.5,en;q=0.3
    #IE6/7 de
    #nil if nothing matches
    def best_locale_in(locales)
      formatted_sorted_locales(locales).each do |candidate|
        return candidate if not available_locales
        return candidate if available_locales.include?(candidate)
        return candidate[0..1] if available_locales.include?(candidate[0..1])#available locales include a langauge
      end
      return nil#nothing found im sorry :P
    end

    #turn off translation if none was defined to disable all resulting errors
    def silence_errors
      require 'fast_gettext/translation_repository/base'
      translation_repositories[text_domain] ||= TranslationRepository::Base.new('x', :path => 'locale')
    end

    private

    # de-de,DE-CH;q=0.9 -> ['de_DE','de_CH']
    def formatted_sorted_locales(locales)
      found = weighted_locales(locales).reject{|x|x.empty?}.sort_by{|l|l.last}.reverse #sort them by weight which is the last entry
      found.flatten.map{|l| format_locale(l)}
    end

    #split the locale and seperate it into different languages
    #de-de,de;q=0.9,en;q=0.8 => [['de-de','de','0.5'], ['en','0.8']]
    def weighted_locales(locales)
      locales = locales.to_s.gsub(/\s/,'')
      found = [[]]
      locales.split(',').each do |part|
        if part =~ /;q=/ #contains language and weight ?
          found.last << part.split(/;q=/)
          found.last.flatten!
          found << []
        else
          found.last << part
        end
      end
      found
    end

    #de-de -> de-DE
    def format_locale(locale)
      locale.sub(/^([a-zA-Z]{2,3})[-_]([a-zA-Z]{2,3})$/){$1.downcase+'_'+$2.upcase}
    end

    def update_current_cache
      caches[text_domain] ||= {}
      caches[text_domain][locale] ||= {}
      caches[text_domain][locale][""] = false #ignore gettext meta key when translating
      self.current_cache = caches[text_domain][locale]

      if ext1
        if !caches[text_domain][ext1]
          caches[text_domain][ext1] = TranslationKey.load_all(ext1)
          caches[text_domain][ext1][""] = false #ignore gettext meta key when translating
        end
        self.current_ext1 = caches[text_domain][ext1]
      else
        self.current_ext1 = nil
      end
      
      if ext2 && ext2.to_s.length > 0
        #commented by rizwan. will see it later
        #version = 0
        #lang = TranslationLanguage.find_by_locale(ext2)
        #version = lang.version if lang
        #if !caches[text_domain][ext2] || !caches[text_domain][ext2][:version] || caches[text_domain][ext2][:version] < version
        if !caches[text_domain][ext2]
          caches[text_domain][ext2] = TranslationKey.load_all(ext2)
          caches[text_domain][ext2][""] = false #ignore gettext meta key when translating
          #caches[text_domain][ext2][:version] = version
        end
        self.current_ext2 = caches[text_domain][ext2]
      else
        self.current_ext2 = nil
      end    
    end
  end
end

