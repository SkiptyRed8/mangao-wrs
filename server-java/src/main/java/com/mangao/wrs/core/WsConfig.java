package com.mangao.wrs.core;

import com.mangao.wrs.service.Realtime;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

/** Real-time updates: the app connects to ws://server:3100/ws?token=... (or ?guest=...). */
@Configuration
@EnableWebSocket
public class WsConfig implements WebSocketConfigurer {
  private final Realtime realtime;

  public WsConfig(Realtime realtime) {
    this.realtime = realtime;
  }

  @Override
  public void registerWebSocketHandlers(WebSocketHandlerRegistry reg) {
    reg.addHandler(realtime, "/ws").setAllowedOriginPatterns("*");
  }
}
