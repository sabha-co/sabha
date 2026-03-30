module TranslationsHelper
  TRANSLATIONS = {
    email_address:  { "🇺🇸": "Your email address", "🇪🇸": "Tu correo electrónico", "🇫🇷": "Votre adresse courriel", "🇮🇳": "आपका ईमेल पता", "🇩🇪": "Ihre E-Mail-Adresse", "🇧🇷": "Seu endereço de e-mail" },
    password: { "🇺🇸": "Enter your password", "🇪🇸": "Introduce tu contraseña", "🇫🇷": "Saisissez votre mot de passe", "🇮🇳": "अपना पासवर्ड दर्ज करें", "🇩🇪": "Geben Sie Ihr Passwort ein", "🇧🇷": "Digite sua senha" },
    password_confirmation: { "🇺🇸": "Confirm your password", "🇪🇸": "Confirma tu contraseña", "🇫🇷": "Confirmez votre mot de passe", "🇮🇳": "अपने पासवर्ड की पुष्टि करें", "🇩🇪": "Bestätigen Sie Ihr Passwort", "🇧🇷": "Confirme sua senha" },
    current_password: { "🇺🇸": "Current password", "🇪🇸": "Contraseña actual", "🇫🇷": "Mot de passe actuel", "🇮🇳": "वर्तमान पासवर्ड", "🇩🇪": "Aktuelles Passwort", "🇧🇷": "Senha atual" },
    one_time_code: { "🇺🇸": "Enter your one-time code", "🇪🇸": "Introduce tu código de una sola vez", "🇫🇷": "Saisissez votre code à usage unique", "🇮🇳": "अपना वन-टाइम कोड दर्ज करें", "🇩🇪": "Geben Sie Ihren Einmalkode ein", "🇧🇷": "Digite seu código único" },
    update_password: { "🇺🇸": "Change password", "🇪🇸": "Cambiar contraseña", "🇫🇷": "Changer le mot de passe", "🇮🇳": "पासवर्ड बदलें", "🇩🇪": "Passwort ändern", "🇧🇷": "Alterar senha" },
    user_name: { "🇺🇸": "Your name", "🇪🇸": "Tu nombre", "🇫🇷": "Votre nom", "🇮🇳": "आपका नाम", "🇩🇪": "Ihren Name", "🇧🇷": "Seu nome" },
    account_name: { "🇺🇸": "Name this account", "🇪🇸": "Nombre de esta cuenta", "🇫🇷": "Nommez ce compte", "🇮🇳": "इस खाते का नाम दें", "🇩🇪": "Benennen Sie dieses Konto", "🇧🇷": "Nomeie esta conta" },
    room_name: { "🇺🇸": "Name the room", "🇪🇸": "Nombrar la sala", "🇫🇷": "Nommez la salle", "🇮🇳": "कमरे का नाम दें", "🇩🇪": "Geben Sie dem Raum einen Namen", "🇧🇷": "Nomeie a sala" },
    room_description: { "🇺🇸": "What's this room about?", "🇪🇸": "¿De qué trata esta sala?", "🇫🇷": "De quoi parle cette salle ?", "🇮🇳": "यह कमरा किस बारे में है?", "🇩🇪": "Worum geht es in diesem Raum?", "🇧🇷": "Sobre o que é esta sala?" },
    invite_message: { "🇺🇸": "Welcome to Sabha. Don't be a stranger—say hello and introduce yourself.", "🇪🇸": "Bienvenido a Sabha. No seas un extraño: di hola y preséntate.", "🇫🇷": "Bienvenue sur Sabha. Ne soyez pas un étranger: dites bonjour et présentez-vous.", "🇮🇳": "Sabha में आपका स्वागत है। अजनबी मत बनो—हैलो कहो और अपना परिचय दो।", "🇩🇪": "Willkommen bei Sabha. Sei kein Fremder – sag Hallo und stell dich vor.", "🇧🇷": "Bem-vindo ao Sabha. Não seja um estranho - diga olá e se apresente." },
    incompatible_browser_messsage: { "🇺🇸": "Upgrade to a supported web browser. Sabha requires a modern web browser. Please use one of the browsers listed below and make sure auto-updates are enabled.", "🇪🇸": "Actualiza a un navegador web compatible. Sabha requiere un navegador web moderno. Utiliza uno de los navegadores listados a continuación y asegúrate de que las actualizaciones automáticas estén habilitadas.", "🇫🇷": "Mettez à jour vers un navigateur web pris en charge. Sabha nécessite un navigateur web moderne. Veuillez utiliser l'un des navigateurs répertoriés ci-dessous et assurez-vous que les mises à jour automatiques sont activées.", "🇮🇳": "समर्थित वेब ब्राउज़र में अपग्रेड करें। Sabha को एक आधुनिक वेब ब्राउज़र की आवश्यकता है। कृपया नीचे सूचीबद्ध ब्राउज़रों में से कोई एक का उपयोग करें और सुनिश्चित करें कि स्वचालित अपडेट्स सक्षम हैं।", "🇩🇪": "Aktualisieren Sie auf einen unterstützten Webbrowser. Sabha erfordert einen modernen Webbrowser. Verwenden Sie bitte einen der unten aufgeführten Browser und stellen Sie sicher, dass automatische Updates aktiviert sind.", "🇧🇷": "Atualize para um navegador web compatível. O Sabha requer um navegador web moderno. Por favor, use um dos navegadores listados abaixo e certifique-se de que as atualizações automáticas estão habilitadas." },
    twitter: { "🇺🇸": "Your Twitter/X profile", "🇪🇸": "Tu perfil de Twitter/X", "🇫🇷": "Votre profil Twitter/X", "🇮🇳": "आपका ट्विटर/X प्रोफ़ाइल", "🇩🇪": "Ihr Twitter/X-Profil", "🇧🇷": "Seu perfil no Twitter/X" },
    linkedin: { "🇺🇸": "Your LinkedIn profile", "🇪🇸": "Tu perfil de LinkedIn", "🇫🇷": "Votre profil LinkedIn", "🇮🇳": "आपका LinkedIn प्रोफ़ाइल", "🇩🇪": "Ihr LinkedIn-Profil", "🇧🇷": "Seu perfil no LinkedIn" },
    website: { "🇺🇸": "Your website", "🇪🇸": "Tu sitio web", "🇫🇷": "Votre site web", "🇮🇳": "आपकी वेबसाइट", "🇩🇪": "Ihre Website", "🇧🇷": "Seu site" },
    bio: { "🇺🇸": "A few words about yourself", "🇪🇸": "Algunas palabras sobre ti mismo", "🇫🇷": "Quelques mots sur vous-même", "🇮🇳": "अपने बारे में कुछ शब्द।", "🇩🇪": "Ein paar Worte über sich selbst", "🇧🇷": "Algumas palavras sobre você" },
    role: { "🇺🇸": "Role", "🇪🇸": "Rol", "🇫🇷": "Rôle", "🇮🇳": "भूमिका", "🇩🇪": "Rolle", "🇧🇷": "Função" },
    webhook_url: { "🇺🇸": "Webhook URL", "🇪🇸": "URL del Webhook", "🇫🇷": "URL du webhook", "🇮🇳": "वेबहुक URL", "🇩🇪": "Webhook-URL", "🇧🇷": "URL do webhook" },
    chat_bots: { "🇺🇸": "Chat bots. With Chat bots, other sites and services can post updates directly to Sabha.", "🇪🇸": "Bots de chat. Con los bots de chat, otros sitios y servicios pueden publicar actualizaciones directamente en Sabha.", "🇫🇷": "Bots de discussion. Avec les bots de discussion, d'autres sites et services peuvent publier des mises à jour directement sur Sabha.", "🇮🇳": "चैट बॉट। चैट बॉट के साथ, अन्य साइटों और सेवाएं सीधे Sabha में अपडेट पोस्ट कर सकती हैं।", "🇩🇪": "Chat-Bots. Mit Chat-Bots können andere Websites und Dienste Updates direkt in Sabha veröffentlichen.", "🇧🇷": "Bots de bate-papo. Com os bots de bate-papo, outros sites e serviços podem postar atualizações diretamente no Sabha." },
    bot_name: { "🇺🇸": "Name the bot", "🇪🇸": "Nombrar al bot", "🇫🇷": "Nommer le bot", "🇮🇳": "बॉट का नाम दें", "🇩🇪": "Benenne den Bot", "🇧🇷": "Nomeie o bot" },
    custom_styles: { "🇺🇸": "Add custom CSS styles. Use Caution: you could break things.", "🇪🇸": "Agrega estilos CSS personalizados. Usa precaución: podrías romper cosas.", "🇫🇷": "Ajoutez des styles CSS personnalisés. Utilisez avec précaution : vous pourriez casser des choses.", "🇮🇳": "कस्टम CSS स्टाइल जोड़ें। सावधानी बरतें: आप चीज़ों को तोड़ सकते हैं।", "🇩🇪": "Fügen Sie benutzerdefinierte CSS-Stile hinzu. Vorsicht: Sie könnten Dinge kaputt machen.", "🇧🇷": "Adicione estilos CSS personalizados. Use com cautela: você poderia quebrar coisas." }
  }

  def translations_for(translation_key)
    tag.dl(class: "language-list") do
      TRANSLATIONS[translation_key].map do |language, translation|
        concat tag.dt(language)
        concat tag.dd(translation, class: "margin-none")
      end
    end
  end

  def translation_button(translation_key)
    tag.details(class: "position-relative", tabindex: -1, data: { controller: "popup", action: "keydown.esc->popup#close toggle->popup#toggle click@document->popup#closeOnClickOutside", popup_orientation_top_class: "popup-orientation-top" }) do
      tag.summary(class: "btn", tabindex: -1) do
        concat image_tag("globe.svg", size: 20, aria: { hidden: "true" }, class: "color-icon")
        concat tag.span("Translate", class: "for-screen-reader")
      end +
      tag.div(class: "lanuage-list-menu shadow", data: { popup_target: "menu" }) do
        translations_for(translation_key)
      end
    end
  end
end
