class TranslationKey < ActiveRecord::Base
  has_many :translations, :class_name => 'TranslationText', :dependent => :destroy
  
  xss_terminate :sanitize  => [:key]
  
  accepts_nested_attributes_for :translations, :allow_destroy => true

  validates_uniqueness_of :key
  validates_presence_of :key

  attr_accessible :key, :translations, :translations_attributes,  :override, :front_end, :custom

  before_save :normalize_newlines

  def to_label
    self.key.to_s
  end

  def self.translation(key, locale)
    # p "#{key} #{locale}"
    return if !key || key.to_s.length == 0
    key = key.to_s[0..254]
    return "<b class='tk'>#{key}</b>" if locale == "xx" && key && !key["format"] && !(key[0..4] == "date.") && !(key[0..4] == "time.") && key != "countries"

    return unless translation_key = find_by_key(newline_normalize(key))
    return unless translation_text = translation_key.translations.find_by_locale(locale)
    translation_text.text
  end

  def self.available_locales
    @@available_locales ||= TranslationText.count(:group=>:locale).keys.sort
  end

  protected

  def self.newline_normalize(s)
    s.to_s.gsub("\r\n", "\n")
  end

  def normalize_newlines
    self.key = self.class.newline_normalize(key)
  end

  def self.load_all(locale)
    translation_texts = TranslationText.find(:all, :conditions=>["locale = ?", locale], :include=>[:translation_key])
    translation_texts
    map = {}
    for text in translation_texts
	  if text && text.translation_key
        map[text.translation_key.key] = text.text
      end
    end
    return map
  end

end
