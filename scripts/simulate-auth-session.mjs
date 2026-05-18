#!/usr/bin/env node

import { createServer } from 'node:http'
import { randomUUID } from 'node:crypto'

const isSimulatorServerMode = process.argv.includes('--serve-simulator')
const accessTokenTtlMs = Number(
  process.env.WALKCALC_SIM_ACCESS_TTL_MS ?? (isSimulatorServerMode ? 2_000 : 250),
)
const refreshTokenTtlMs = Number(
  process.env.WALKCALC_SIM_REFRESH_TTL_MS ??
    (isSimulatorServerMode ? 5 * 60_000 : 30_000),
)

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function parseCookies(header = '') {
  return Object.fromEntries(
    header
      .split(';')
      .map((part) => part.trim())
      .filter(Boolean)
      .map((part) => {
        const index = part.indexOf('=')
        return index === -1
          ? [part, '']
          : [part.slice(0, index), part.slice(index + 1)]
      }),
  )
}

function setCookieHeaders(accessToken, refreshToken) {
  return [
    `accessToken=${accessToken}; Path=/; HttpOnly; Max-Age=1`,
    `refreshToken=${refreshToken}; Path=/; HttpOnly; Max-Age=30`,
  ]
}

function jsonResponse(res, status, body, cookies = []) {
  res.writeHead(status, {
    'content-type': 'application/json',
    ...(cookies.length ? { 'set-cookie': cookies } : {}),
  })
  res.end(JSON.stringify(body))
}

async function jsonBody(req) {
  const chunks = []
  for await (const chunk of req) {
    chunks.push(chunk)
  }
  if (!chunks.length) {
    return {}
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'))
}

function makeAuthServer(options = {}) {
  const state = {
    accessTokens: new Map(),
    currentRefreshToken: options.seedRefreshToken ?? null,
    refreshExpiresAt: options.seedRefreshToken
      ? Date.now() + refreshTokenTtlMs
      : 0,
    revoked: false,
    refreshCount: 0,
  }

  function issueSession() {
    const accessToken = `access-${randomUUID()}`
    const refreshToken = `refresh-${randomUUID()}`
    state.accessTokens.set(accessToken, Date.now() + accessTokenTtlMs)
    state.currentRefreshToken = refreshToken
    state.refreshExpiresAt = Date.now() + refreshTokenTtlMs
    state.revoked = false
    return { accessToken, refreshToken }
  }

  function issueAccessToken() {
    const accessToken = `access-${randomUUID()}`
    state.accessTokens.set(accessToken, Date.now() + accessTokenTtlMs)
    return accessToken
  }

  function protectedResponse(req, res, data) {
    const cookies = parseCookies(req.headers.cookie)
    const authHeader = req.headers.authorization ?? ''
    const bearerToken = authHeader.startsWith('Bearer ')
      ? authHeader.slice('Bearer '.length)
      : undefined
    const accessToken = bearerToken || cookies.accessToken
    const expiresAt = accessToken ? state.accessTokens.get(accessToken) : 0

    if (!accessToken || !expiresAt || expiresAt <= Date.now()) {
      jsonResponse(res, 401, {
        success: false,
        message: 'Invalid or expired token',
      })
      return
    }

    jsonResponse(res, 200, {
      success: true,
      data,
    })
  }

  const server = createServer(async (req, res) => {
    if (options.logRequests) {
      const cookies = parseCookies(req.headers.cookie)
      console.log(
        `SIM_SERVER_REQUEST ${req.method} ${req.url} auth=${Boolean(req.headers.authorization)} cookies=${Object.keys(cookies).join(',') || '-'}`,
      )
    }

    if (req.method === 'POST' && req.url === '/auth/login') {
      const { accessToken, refreshToken } = issueSession()
      jsonResponse(
        res,
        200,
        {
          success: true,
          data: {
            accessToken,
            refreshToken,
            accessTokenExpiresIn: `${accessTokenTtlMs}ms`,
            refreshTokenExpiresIn: `${refreshTokenTtlMs}ms`,
            user: { userId: 'user-1', profile: { name: 'Hong' } },
          },
        },
        setCookieHeaders(accessToken, refreshToken),
      )
      return
    }

    if (req.method === 'GET' && req.url === '/auth/info') {
      protectedResponse(req, res, {
        userId: 'user-1',
        profile: { name: 'Hong' },
      })
      return
    }

    if (req.method === 'GET' && req.url === '/walkcalc/home/summary') {
      protectedResponse(req, res, { totalBalance: '0' })
      return
    }

    if (req.method === 'GET' && req.url?.startsWith('/walkcalc/groups/my')) {
      protectedResponse(req, res, [])
      return
    }

    if (req.method === 'POST' && req.url === '/auth/refreshToken') {
      const cookies = parseCookies(req.headers.cookie)
      const body = await jsonBody(req).catch(() => ({}))
      const refreshToken = body.refreshToken || cookies.refreshToken

      if (
        !refreshToken ||
        state.revoked ||
        refreshToken !== state.currentRefreshToken ||
        state.refreshExpiresAt <= Date.now()
      ) {
        if (options.logRequests) {
          console.log(
            `SIM_SERVER_REFRESH rejected sent=${refreshToken ?? '-'} expected=${state.currentRefreshToken ?? '-'} revoked=${state.revoked}`,
          )
        }
        if (refreshToken && refreshToken !== state.currentRefreshToken) {
          state.revoked = true
        }
        jsonResponse(res, 401, {
          success: false,
          message: 'Invalid or expired refresh token',
        })
        return
      }

      const accessToken = issueAccessToken()
      const nextRefreshToken = `refresh-${randomUUID()}`
      state.currentRefreshToken = nextRefreshToken
      state.refreshExpiresAt = Date.now() + refreshTokenTtlMs
      state.refreshCount += 1
      if (options.logRequests) {
        console.log(
          `SIM_SERVER_REFRESH ok access=${accessToken} nextRefresh=${nextRefreshToken}`,
        )
      }

      jsonResponse(
        res,
        200,
        {
          success: true,
          data: {
            accessToken,
            refreshToken: nextRefreshToken,
            accessTokenExpiresIn: `${accessTokenTtlMs}ms`,
            refreshTokenExpiresIn: `${refreshTokenTtlMs}ms`,
          },
        },
        setCookieHeaders(accessToken, nextRefreshToken),
      )
      return
    }

    jsonResponse(res, 404, { success: false, message: 'not found' })
  })

  return {
    state,
    listen: () =>
      new Promise((resolve) => {
        server.listen(0, '127.0.0.1', () => {
          const address = server.address()
          resolve({
            baseURL: `http://${address.address}:${address.port}`,
            close: () =>
              new Promise((closeResolve) => server.close(closeResolve)),
          })
        })
      }),
  }
}

class NativeAuthSimulator {
  constructor(baseURL, label) {
    this.baseURL = baseURL
    this.label = label
    this.savedAccessToken = null
    this.savedRefreshToken = null
    this.cookies = new Map()
    this.route = 'resolving'
    this.log = []
  }

  clone(label, { keepCookies }) {
    const next = new NativeAuthSimulator(this.baseURL, label)
    next.savedAccessToken = this.savedAccessToken
    next.savedRefreshToken = this.savedRefreshToken
    if (keepCookies) {
      next.cookies = new Map(this.cookies)
    }
    return next
  }

  cookieHeader() {
    return [...this.cookies.entries()]
      .map(([name, value]) => `${name}=${value}`)
      .join('; ')
  }

  hasRefreshCookie() {
    return this.cookies.has('refreshToken')
  }

  importSetCookies(headers) {
    const setCookie = headers.getSetCookie?.() ?? []
    for (const raw of setCookie) {
      const [pair] = raw.split(';')
      const index = pair.indexOf('=')
      if (index !== -1) {
        const name = pair.slice(0, index)
        const value = pair.slice(index + 1)
        this.cookies.set(name, value)
        if (name === 'refreshToken') {
          this.savedRefreshToken = value
        }
      }
    }
  }

  async rawRequest(
    method,
    path,
    { token, useCookies = false, body: requestBody, signal } = {},
  ) {
    const headers = {
      'content-type': 'application/json',
      'x-locale': 'en',
    }
    if (token) {
      headers.authorization = `Bearer ${token}`
    }
    if (useCookies && this.cookies.size) {
      headers.cookie = this.cookieHeader()
    }

    const response = await fetch(`${this.baseURL}${path}`, {
      method,
      headers,
      body: requestBody ? JSON.stringify(requestBody) : undefined,
      signal,
    })
    this.importSetCookies(response.headers)
    const body = await response.json().catch(() => ({}))
    this.log.push({
      method,
      path,
      status: response.status,
      sentBearer: Boolean(token),
      sentRefreshCookie: Boolean(
        useCookies && headers.cookie?.includes('refreshToken='),
      ),
      sentRefreshBody: Boolean(requestBody?.refreshToken),
    })
    return { status: response.status, body }
  }

  async login() {
    const response = await this.rawRequest('POST', '/auth/login', {
      useCookies: true,
    })
    this.savedAccessToken = response.body.data.accessToken
    this.savedRefreshToken = response.body.data.refreshToken
    this.route = 'authenticated'
    return response
  }

  async refreshAccessToken() {
    const body = this.savedRefreshToken
      ? { refreshToken: this.savedRefreshToken }
      : undefined
    if (!this.hasRefreshCookie() && !body) {
      throw new Error('authRefresh: missing refresh credential')
    }
    const response = await this.rawRequest('POST', '/auth/refreshToken', {
      useCookies: true,
      body,
    })
    if (response.status < 200 || response.status >= 300) {
      throw new Error(`authRefresh: refresh rejected ${response.status}`)
    }
    this.savedAccessToken = response.body.data.accessToken
    this.savedRefreshToken = response.body.data.refreshToken
    return this.savedAccessToken
  }

  async requestProtected(path) {
    let response = await this.rawRequest('GET', path, {
      token: this.savedAccessToken,
      useCookies: false,
    })

    if (response.status === 401 || response.status === 403) {
      await this.refreshAccessToken()
      response = await this.rawRequest('GET', path, {
        token: this.savedAccessToken,
        useCookies: false,
      })
      if (response.status === 401 || response.status === 403) {
        throw new Error('authRefresh: retried request rejected')
      }
    }

    return response
  }

  async bootstrap() {
    this.route = 'resolving'
    if (!this.savedAccessToken) {
      this.route = 'loginRequired'
      return this.route
    }

    try {
      const response = await this.requestProtected('/auth/info')
      this.route = response.status === 200 ? 'authenticated' : 'loginRequired'
    } catch (error) {
      this.route = 'loginRequired'
      this.log.push({
        method: 'BOOTSTRAP',
        path: '/auth/info',
        status: 'loginRequired',
        error: error.message,
      })
    }
    return this.route
  }

  async backgroundRefreshThenSuspend() {
    this.route = 'authenticated'
    const controller = new AbortController()
    const request = this.rawRequest('GET', '/walkcalc/home/summary', {
      token: this.savedAccessToken,
      signal: controller.signal,
    })
    controller.abort()
    try {
      await request
    } catch (error) {
      this.log.push({
        method: 'GET',
        path: '/walkcalc/home/summary',
        status: 'cancelled',
        appPolicy: 'silent non-auth failure; foreground activation performs auth check',
      })
    }
  }

  async foregroundActivation() {
    try {
      await this.requestProtected('/auth/info')
      await this.requestProtected('/walkcalc/home/summary')
      this.route = 'authenticated'
    } catch (error) {
      this.route = 'loginRequired'
      this.log.push({
        method: 'FOREGROUND',
        path: '/auth/info',
        status: 'loginRequired',
        error: error.message,
      })
    }
  }
}

function printScenario(title, simulator, extra = {}) {
  console.log(`\n=== ${title} ===`)
  for (const item of simulator.log) {
    const details = [
      item.sentBearer ? 'Bearer' : null,
      item.sentRefreshCookie ? 'refreshCookie' : null,
      item.sentRefreshBody ? 'refreshBody' : null,
      item.error ? `error=${item.error}` : null,
      item.appPolicy ? `policy=${item.appPolicy}` : null,
    ]
      .filter(Boolean)
      .join(', ')
    console.log(
      `${item.method} ${item.path} -> ${item.status}${details ? ` (${details})` : ''}`,
    )
  }
  console.log(`savedAccessToken=${simulator.savedAccessToken ? 'present' : 'missing'}`)
  console.log(`savedRefreshToken=${simulator.savedRefreshToken ? 'present' : 'missing'}`)
  console.log(`refreshCookie=${simulator.hasRefreshCookie() ? 'present' : 'missing'}`)
  console.log(`route=${simulator.route}`)
  for (const [key, value] of Object.entries(extra)) {
    console.log(`${key}=${value}`)
  }
}

async function main() {
  if (isSimulatorServerMode) {
    const seedRefreshToken =
      process.env.WALKCALC_SIM_REFRESH_TOKEN ?? 'refresh-seed'
    const seedAccessToken =
      process.env.WALKCALC_SIM_ACCESS_TOKEN ?? 'expired-access'
    const authServer = makeAuthServer({
      seedRefreshToken,
      logRequests: true,
    })
    const server = await authServer.listen()
    console.log(
      `SIM_SERVER_READY ${JSON.stringify({
        baseURL: server.baseURL,
        accessToken: seedAccessToken,
        refreshToken: seedRefreshToken,
        accessTokenTtlMs,
      })}`,
    )
    process.on('SIGTERM', async () => {
      await server.close()
      process.exit(0)
    })
    process.on('SIGINT', async () => {
      await server.close()
      process.exit(0)
    })
    return
  }

  const authServer = makeAuthServer()
  const server = await authServer.listen()
  console.log(`Mock auth server: ${server.baseURL}`)

  try {
    const app = new NativeAuthSimulator(server.baseURL, 'initial app')
    await app.login()
    await sleep(accessTokenTtlMs + 80)
    await app.requestProtected('/auth/info')
    printScenario('Warm request after expired access token: refresh succeeds', app, {
      refreshCount: authServer.state.refreshCount,
    })

    const persisted = app.clone('cold start with cookie', { keepCookies: true })
    await sleep(accessTokenTtlMs + 80)
    await persisted.bootstrap()
    printScenario('Cold start with saved access token and persisted refresh cookie', persisted, {
      expected: 'authenticated',
    })
    app.savedAccessToken = persisted.savedAccessToken
    app.savedRefreshToken = persisted.savedRefreshToken
    app.cookies = new Map(persisted.cookies)

    const lostCookie = app.clone('cold start without cookie', { keepCookies: false })
    await sleep(accessTokenTtlMs + 80)
    await lostCookie.bootstrap()
    printScenario('Cold start with saved access token but lost refresh cookie', lostCookie, {
      expected: 'authenticated via local refresh token body',
    })
    app.savedAccessToken = lostCookie.savedAccessToken
    app.savedRefreshToken = lostCookie.savedRefreshToken
    app.cookies = new Map(lostCookie.cookies)

    const cancelled = app.clone('suspend during request', { keepCookies: true })
    await cancelled.backgroundRefreshThenSuspend()
    await sleep(accessTokenTtlMs + 80)
    await cancelled.foregroundActivation()
    printScenario('App suspend cancels an in-flight request, then foreground refresh runs', cancelled, {
      expected: 'authenticated after foreground auth check retries with refresh token',
    })

    const offline = app.clone('cold start with transport failure', {
      keepCookies: true,
    })
    offline.baseURL = 'http://127.0.0.1:9'
    await offline.bootstrap()
    printScenario('Cold start when auth validation has a transport failure', offline, {
      expected:
        'current WalkcalcStore policy maps fetchUser nil to loginRequired even though token was not proven invalid',
    })
  } finally {
    await server.close()
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
