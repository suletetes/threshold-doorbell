// Typed application errors. All 4xx/5xx responses use the envelope
// { error: { code, message, requestId } } from design.md §4.

export type ErrorCode =
  | 'oauth_init_failed'
  | 'state_mismatch'
  | 'code_exchange_failed'
  | 'refresh_failed'
  | 'unauthorized'
  | 'rate_limited'
  | 'ring_unavailable'
  | 'ring_contract_invalid'
  | 'bad_signature'
  | 'schema'
  | 'resident_mismatch'
  | 'not_found'
  | 'conflict'
  | 'internal';

export interface ErrorEnvelope {
  error: {
    code: ErrorCode;
    message: string;
    requestId: string;
  };
}

export class AppError extends Error {
  readonly code: ErrorCode;
  readonly statusCode: number;

  constructor(code: ErrorCode, statusCode: number, message: string) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.statusCode = statusCode;
  }

  toEnvelope(requestId: string): ErrorEnvelope {
    return { error: { code: this.code, message: this.message, requestId } };
  }
}

export const errors = {
  oauthInitFailed: () =>
    new AppError('oauth_init_failed', 500, 'Could not start sign-in. Please try again.'),
  stateMismatch: () =>
    new AppError('state_mismatch', 400, 'Sign-in could not be verified. Please try again.'),
  codeExchangeFailed: () =>
    new AppError('code_exchange_failed', 400, 'Sign-in could not be completed. Please try again.'),
  refreshFailed: () =>
    new AppError('refresh_failed', 401, 'Your session needs to be renewed. Please sign in again.'),
  unauthorized: () => new AppError('unauthorized', 401, 'You need to sign in to continue.'),
  rateLimited: () => new AppError('rate_limited', 429, 'Too many requests. Please try again shortly.'),
  ringUnavailable: () =>
    new AppError('ring_unavailable', 502, 'Ring is temporarily unavailable. Please try again.'),
  ringContractInvalid: () =>
    new AppError('ring_contract_invalid', 502, 'Received an unexpected response from Ring.'),
  badSignature: () => new AppError('bad_signature', 401, 'Signature verification failed.'),
  schema: (message = 'The request could not be understood.') => new AppError('schema', 400, message),
  residentMismatch: () =>
    new AppError('resident_mismatch', 403, 'You can only access your own data.'),
  notFound: (message = 'Not found.') => new AppError('not_found', 404, message),
  conflict: (message = 'That record already exists.') => new AppError('conflict', 409, message),
  internal: () => new AppError('internal', 500, 'Something went wrong. Please try again.'),
};
