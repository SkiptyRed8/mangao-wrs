package com.mangao.wrs.core;

import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.databind.JsonSerializer;
import com.fasterxml.jackson.databind.SerializerProvider;
import com.fasterxml.jackson.databind.module.SimpleModule;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Instant;
import java.util.concurrent.TimeUnit;
import org.springframework.boot.autoconfigure.jackson.Jackson2ObjectMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.CacheControl;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {

  /** The app runs on another port (Chrome) or on phones: allow every origin, like cors() before. */
  @Override
  public void addCorsMappings(CorsRegistry reg) {
    reg.addMapping("/**").allowedOriginPatterns("*").allowedMethods("*").allowedHeaders("*").exposedHeaders("Content-Disposition");
  }

  /** Damaged-gallon photos (random file names). */
  @Override
  public void addResourceHandlers(ResourceHandlerRegistry reg) {
    reg.addResourceHandler("/uploads/**")
        .addResourceLocations(Env.uploadsDir().toUri().toString() + "/")
        .setCacheControl(CacheControl.maxAge(7, TimeUnit.DAYS));
  }

  /** Dates in JSON like before: "2026-10-14T01:40:00.000Z". */
  @Bean
  public Jackson2ObjectMapperBuilderCustomizer jsonDates() {
    SimpleModule m = new SimpleModule();
    m.addSerializer(Instant.class, new JsonSerializer<>() {
      @Override
      public void serialize(Instant v, JsonGenerator g, SerializerProvider p) throws IOException {
        g.writeString(Clock.iso(v));
      }
    });
    m.addSerializer(Double.class, new JsonSerializer<>() {
      @Override
      public void serialize(Double v, JsonGenerator g, SerializerProvider p) throws IOException {
        if (v == Math.rint(v) && !v.isInfinite() && Math.abs(v) < 1e15) g.writeNumber(v.longValue());
        else g.writeNumber(v);
      }
    });
    return b -> b.modulesToInstall(m);
  }

  /** Tests only (NODE_ENV=test): the X-Test-Now header sets the clock for that request. */
  @Bean
  public OncePerRequestFilter testClock() {
    return new OncePerRequestFilter() {
      @Override
      protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
          throws ServletException, IOException {
        if (!Env.testMode()) {
          chain.doFilter(req, res);
          return;
        }
        Clock.setRequestNow(req.getHeader("X-Test-Now"));
        try {
          chain.doFilter(req, res);
        } finally {
          Clock.clearRequestNow();
        }
      }
    };
  }
}
