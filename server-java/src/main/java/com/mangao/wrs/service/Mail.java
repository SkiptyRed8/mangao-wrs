package com.mangao.wrs.service;

import com.mangao.wrs.core.Env;
import jakarta.mail.internet.MimeMessage;
import java.util.Properties;
import org.springframework.mail.javamail.JavaMailSenderImpl;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Component;

/**
 * Sends emails (the forgot-password code) through Gmail SMTP with Spring Boot Mail (JavaMail).
 * While SMTP_USER is empty in .env, nothing is sent: the code is printed in the server window
 * and, outside production, also returned to the app so the flow can be shown in a demo.
 */
@Component
public class Mail {
  private JavaMailSenderImpl sender;

  public static boolean ready() {
    return !Env.smtpUser().isEmpty() && !Env.smtpPass().isEmpty();
  }

  private synchronized JavaMailSenderImpl sender() {
    if (sender == null) {
      JavaMailSenderImpl s = new JavaMailSenderImpl();
      s.setHost(Env.smtpHost());
      s.setPort(Env.smtpPort());
      s.setUsername(Env.smtpUser());
      s.setPassword(Env.smtpPass());
      s.setDefaultEncoding("UTF-8");
      Properties p = s.getJavaMailProperties();
      p.put("mail.smtp.auth", "true");
      if (Env.smtpPort() == 465) {
        p.put("mail.smtp.ssl.enable", "true");
      } else {
        p.put("mail.smtp.starttls.enable", "true");
      }
      p.put("mail.smtp.connectiontimeout", "15000");
      p.put("mail.smtp.timeout", "15000");
      p.put("mail.smtp.writetimeout", "15000");
      sender = s;
    }
    return sender;
  }

  /** a.lim@gmail.com -> a••••@gmail.com */
  public static String maskEmail(String email) {
    int at = email.indexOf('@');
    if (at < 0) return email;
    return (at > 0 ? email.substring(0, 1) : "") + "••••@" + email.substring(at + 1);
  }

  /** Plain-words reason and fix for a Gmail error, printed in the server window. */
  public static String hint(Exception err) {
    StringBuilder sb = new StringBuilder();
    for (Throwable t = err; t != null; t = t.getCause()) sb.append(t.getClass().getSimpleName()).append(' ').append(t.getMessage()).append(' ');
    String m = sb.toString();
    if (m.matches("(?is).*(AuthenticationFailed|535|Invalid login|Username and Password not accepted|BadCredentials).*")) {
      return "Gmail refused the login. Check SMTP_USER is the full Gmail address, SMTP_PASS is a 16-letter App Password (not your normal Gmail password), and 2-Step Verification is ON for that Google account. Make a new App Password if unsure.";
    }
    if (m.matches("(?is).*(timed out|Connection refused|UnknownHost|Couldn't connect|connection reset|SocketException).*")) {
      return "Cannot reach smtp.gmail.com. Check the internet connection; an antivirus or firewall may block port 465 (try SMTP_PORT=587).";
    }
    if (m.matches("(?is).*(534|5\\.7\\.9|Application-specific).*")) return "Google wants an App Password here, not the normal password.";
    if (m.matches("(?is).*(550|553|invalid.*recipient|No such user).*")) return "Gmail did not accept the receiving email address.";
    return "See the message above.";
  }

  /** Sends the 6-digit reset code. Returns true when sent, false when email is not set up. */
  public boolean sendResetCode(String to, String name, String code) throws Exception {
    if (!ready()) {
      if (!Env.testMode()) System.out.println("[email not set up] password reset code for " + to + ": " + code);
      return false;
    }
    JavaMailSenderImpl s = sender();
    MimeMessage msg = s.createMimeMessage();
    MimeMessageHelper h = new MimeMessageHelper(msg, true, "UTF-8");
    h.setFrom(new jakarta.mail.internet.InternetAddress(Env.mailFrom()));
    h.setTo(to);
    h.setSubject(code + " is your Mangao password reset code");
    String text = "Hi " + name + ",\n\n"
        + "Your code to reset your password is " + code + ".\n"
        + "It works for 10 minutes. If you did not ask for this, you can ignore this email.\n\n"
        + "Mangao Water Refilling Station";
    String html = "<p>Hi " + escape(name) + ",</p>"
        + "<p>Your code to reset your password is</p><p style=\"font-size:28px;font-weight:700;letter-spacing:6px\">" + code + "</p>"
        + "<p>It works for 10 minutes. If you did not ask for this, you can ignore this email.</p>"
        + "<p>Mangao Water Refilling Station</p>";
    h.setText(text, html);
    s.send(msg);
    return true;
  }

  private static String escape(String s) {
    return String.valueOf(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;");
  }
}
